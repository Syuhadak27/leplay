package com.leplay.syd

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale




object SearchHistory {
    private const val PREFS_NAME = "search_history_prefs"
    private const val KEY_HISTORY = "recent_queries"
    private const val KEY_HIDDEN = "hidden_queries"
    private const val KEY_MIGRATED_TO_ACCOUNT = "migrated_to_account"
    private const val MAX_HISTORY = 30
    private const val MAX_HIDDEN = 200
    private const val GUEST = "guest"

    private var prefs: SharedPreferences? = null

    /** Account id currently backing [queries]; null until [init] or [useAccount]. */
    private var scope: String? = null

    /** Searches typed on this device for the active account. */
    private var localQueries: List<String> = emptyList()

    /** Search history downloaded from the signed-in YouTube account. */
    private var remoteQueries: List<String> = emptyList()

    /** Server entries removed locally, so a later sync cannot resurrect them. */
    private var hiddenQueries: Set<String> = emptySet()

    var queries by mutableStateOf<List<String>>(emptyList())
        private set

    /** True while the account history is being refreshed from YouTube. */
    var syncing by mutableStateOf(false)
        private set

    /** True once the signed-in account's history has loaded successfully. */
    var accountSynced by mutableStateOf(false)
        private set

    fun init(context: Context) {
        if (prefs == null) {
            prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }
        useAccount(Account.activeAccountId)
    }

    /**
     * Point the history at [accountId], or at the signed-out guest store.
     * Switching accounts must not leak one profile's recent searches into
     * another, so every account gets its own local key.
     */
    fun useAccount(accountId: String?) {
        val next = accountId?.takeIf { it.isNotBlank() } ?: GUEST
        if (next == scope) return
        scope = next
        remoteQueries = emptyList()
        accountSynced = false
        localQueries = loadLocal()
        hiddenQueries = readList(scopedKey(KEY_HIDDEN)).mapTo(HashSet()) { it.lowercase(Locale.ROOT) }
        publish()
    }

    fun add(query: String) {
        useAccount(Account.activeAccountId)
        val q = query.trim()
        if (q.isEmpty()) return
        val key = q.lowercase(Locale.ROOT)
        hiddenQueries = hiddenQueries - key
        localQueries = (listOf(q) + localQueries.filterNot { it.equals(q, ignoreCase = true) })
            .take(MAX_HISTORY)
        persistLocal()
        persistHidden()
        publish()
    }

    fun remove(query: String) {
        useAccount(Account.activeAccountId)
        val q = query.trim()
        if (q.isEmpty()) return
        val key = q.lowercase(Locale.ROOT)
        hiddenQueries = (hiddenQueries + key).toList().takeLast(MAX_HIDDEN).toSet()
        localQueries = localQueries.filterNot { it.equals(q, ignoreCase = true) }
        remoteQueries = remoteQueries.filterNot { it.equals(q, ignoreCase = true) }
        persistLocal()
        persistHidden()
        publish()
    }

    fun clear() {
        useAccount(Account.activeAccountId)
        val visible = queries.map { it.lowercase(Locale.ROOT) }
        hiddenQueries = (hiddenQueries + visible).toList().takeLast(MAX_HIDDEN).toSet()
        localQueries = emptyList()
        remoteQueries = emptyList()
        persistLocal()
        persistHidden()
        publish()
    }

    /**
     * Pull the signed-in account's search history from YouTube's history
     * page. Queries are merged with the local list, newest first, so a
     * search made on another device or on the web shows up here too.
     */
    suspend fun syncFromAccount() {
        val account = Account.activeAccountId ?: return
        useAccount(account)
        if (syncing) return
        syncing = true
        try {
            // The history feed and the search box's zero-prefix suggestions
            // expose different slices of the same account data. Merge both:
            // the feed is more complete, while the zero-prefix completion is
            // what YouTube itself shows as "recent searches" in the search box.
            val feed = runCatching { InnerTube.searchHistory() }.getOrNull()
            val recent = runCatching {
                InnerTube.searchSuggestions("")
                    .filter { it.history }
                    .map { it.text }
            }.getOrNull()
            // Ignore a response that arrives after an account switch. If both
            // requests fail, keep the previous list instead of wiping it.
            if (Account.activeAccountId == account && (feed != null || recent != null)) {
                remoteQueries = (recent.orEmpty() + feed.orEmpty())
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                    .distinctBy { it.lowercase(Locale.ROOT) }
                accountSynced = true
                publish()
            }
        } finally {
            syncing = false
        }
    }

    private fun publish() {
        val seen = HashSet<String>()
        val out = ArrayList<String>(MAX_HISTORY)
        // Local entries come first so a query typed just now stays at the
        // top even before the server has recorded it.
        for (query in localQueries + remoteQueries) {
            val q = query.trim()
            if (q.isEmpty()) continue
            val key = q.lowercase(Locale.ROOT)
            if (key in hiddenQueries) continue
            if (!seen.add(key)) continue
            out += q
            if (out.size >= MAX_HISTORY) break
        }
        queries = out
    }

    private fun loadLocal(): List<String> {
        val ownKey = scopedKey(KEY_HISTORY)
        if (prefs?.contains(ownKey) == true) return readList(ownKey)

        // First signed-in run after an update: carry the existing guest
        // history into the active account once instead of showing an
        // empty list after the user signs in.
        if (scope != GUEST && prefs?.getBoolean(KEY_MIGRATED_TO_ACCOUNT, false) == false) {
            val legacy = readList(KEY_HISTORY)
            if (legacy.isNotEmpty()) saveList(ownKey, legacy)
            prefs?.edit()?.putBoolean(KEY_MIGRATED_TO_ACCOUNT, true)?.apply()
            return legacy
        }
        return readList(ownKey)
    }

    private fun scopedKey(base: String): String {
        val current = scope ?: GUEST
        return if (current == GUEST) base else "$base:$current"
    }

    private fun persistLocal() = saveList(scopedKey(KEY_HISTORY), localQueries)

    private fun persistHidden() = saveList(scopedKey(KEY_HIDDEN), hiddenQueries.toList())

    private fun readList(key: String): List<String> =
        prefs?.getString(key, null)
            ?.split('\n')
            ?.map { it.trim() }
            ?.filter { it.isNotBlank() }
            .orEmpty()

    private fun saveList(key: String, values: List<String>) {
        prefs?.edit()?.putString(key, values.joinToString("\n"))?.apply()
    }
}
