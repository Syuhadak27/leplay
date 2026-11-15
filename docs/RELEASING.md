# Push Kode dan Publikasi Rilis

LePlay memakai GitHub Actions untuk build dan publish APK. Workflow-nya ada di
[`.github/workflows/release.yml`](../.github/workflows/release.yml).

## Prasyarat

- Punya akses push ke <https://github.com/Syuhadak27/leplay>
- Git, plus JDK 21 dan Android SDK untuk build lokal (opsional)
- [GitHub CLI](https://cli.github.com/) (`gh`) untuk cek status dan release (opsional)

```bash
git clone git@github.com:Syuhadak27/leplay.git
cd leplay
git remote -v
# origin  git@github.com:Syuhadak27/leplay.git
```

Gunakan branch `main` untuk rilis.

---

## Alur normal: push kode, rilis otomatis

1. Lakukan perubahan dan tes terlebih dahulu.
2. Commit lalu push ke `main`:

```bash
git add .
git commit -m "feat: jelaskan perubahan kamu"
git push origin main
```

3. GitHub Actions akan berjalan otomatis dan:

   - membaca `versionName` saat ini dari `app/build.gradle.kts`;
   - menaikkan versi patch dan menambah `versionCode`;
   - build `:app:assembleRelease`;
   - commit perubahan versi sebagai `LePlay X.Y.Z [skip ci]`;
   - membuat dan push tag `vX.Y.Z`;
   - publish GitHub Release berisi `LePlay.apk`.

   Contoh: push dari `0.1.7` (`versionCode 144`) menghasilkan `0.1.8`
   (`versionCode 145`), tag `v0.1.8`, dan release `LePlay 0.1.8`.

4. Pantau proses build:

```bash
gh run list --repo Syuhadak27/leplay --workflow release.yml --limit 5
gh run watch RUN_ID --repo Syuhadak27/leplay
```

Atau buka <https://github.com/Syuhadak27/leplay/actions>.

5. Cek atau download release:

```bash
gh release view --repo Syuhadak27/leplay

# Download APK dari release terbaru
curl -L -o LePlay.apk \
  https://github.com/Syuhadak27/leplay/releases/latest/download/LePlay.apk
```

Kamu tidak perlu mengubah `versionCode` atau `versionName` untuk rilis normal.
Workflow yang mengurus kenaikan versi. Commit perubahan versi berisi `[skip ci]`,
jadi tidak memicu rilis kedua.

---

## Lewati rilis untuk perubahan dokumentasi saja

Tambahkan `[skip ci]` di pesan commit kalau push tersebut tidak perlu membuat
release:

```bash
git add README.md docs/
git commit -m "docs: perbarui panduan rilis [skip ci]"
git push origin main
```

GitHub Actions tidak akan berjalan untuk push tersebut.

---

## Trigger manual tanpa perubahan kode

Jalankan workflow dari `main` saat ini dan biarkan workflow membuat rilis patch
berikutnya:

```bash
gh workflow run release.yml --repo Syuhadak27/leplay
gh run list --repo Syuhadak27/leplay --workflow release.yml --limit 5
```

Kamu juga bisa memakai **Actions → Build & Release → Run workflow** di GitHub.

---

## Rilis berbasis tag (recovery atau versi tertentu)

Push tag akan build versi yang sedang di-set di `app/build.gradle.kts` dan
publish-nya dengan nama tag tersebut. Gunakan cara ini untuk recovery saat
Actions berhenti setelah push perubahan versi tapi sebelum release dibuat, atau
saat `main` sudah berisi `versionName` yang memang ingin dirilis.

```bash
git checkout main
git pull --ff-only origin main

# Pastikan versi sama dengan tag yang akan dibuat.
grep -nE 'versionCode|versionName' app/build.gradle.kts
# Contoh: versionName = "0.1.8"

git tag -a v0.1.8 -m "LePlay 0.1.8"
git push origin v0.1.8
```

Lalu verifikasi:

```bash
gh run list --repo Syuhadak27/leplay --workflow release.yml --limit 5
gh release view v0.1.8 --repo Syuhadak27/leplay
```

Selalu buat tag dari commit yang `versionName`-nya cocok dengan tag, dan jangan
pakai ulang tag yang sudah punya release.

---

## Build lokal (opsional)

```bash
./gradlew :app:assembleRelease
ls -lh app/build/outputs/apk/release/app-release.apk
```

Build release memakai `app/release.keystore` kalau file itu ada. Pertahankan
keystore yang sama dan `applicationId` yang sama (`com.leplay.syd`) supaya
Android menerima update berikutnya.

---

## Troubleshooting

Lihat langkah yang gagal pada sebuah run:

```bash
gh run view RUN_ID --repo Syuhadak27/leplay --log-failed
```

Jalankan ulang workflow yang gagal:

```bash
gh run rerun RUN_ID --repo Syuhadak27/leplay
```

Hapus dan buat ulang tag hanya kalau release-nya rusak dan tag tersebut belum
dipakai untuk APK yang berfungsi:

```bash
git tag -d v0.1.8
git push origin :refs/tags/v0.1.8
```

Lalu buat dan push lagi dari commit yang benar.
