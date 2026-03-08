# GitHub Actions Setup

## Workflow Configuration

The build workflow (`.github/workflows/build.yml`) supports:

### 1. Monthly Scheduled Builds

Runs automatically on the 1st of each month at 02:00 UTC.

### 2. Manual Trigger

Go to Actions tab -> "Build HPLIP Packages" -> "Run workflow"

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version` | No | (from VERSION file) | HPLIP version to build (e.g., 3.25.8) |
| `create_release` | No | false | Create GitHub release with packages |
| `distros` | No | (all 5 distros) | Comma-separated list of distributions |

### Example Manual Runs

**Build specific version for testing:**
- version: `3.25.8`
- create_release: `false`
- distros: `ubuntu-22.04`

**Build and release all distros:**
- version: (leave empty for VERSION file)
- create_release: `true`
- distros: (leave empty for all)

**Build only RPM distros:**
- distros: `fedora-39,opensuse-15.5`

---

## HPLIP Source Download

**The workflow downloads HPLIP source from SourceForge during build.**

The `hplip-3.25.8.tar.gz` in the repository is NOT used for builds. It is only:
- A reference copy
- Used for local testing without internet
- Not committed to git (should be in .gitignore)

**Download happens in `packages/build-deb.sh` and `packages/build-rpm.sh`:**

```bash
wget -q "https://sourceforge.net/projects/hplip/files/hplip/${VERSION}/hplip-${VERSION}.tar.gz"
```

**This means:**
- SourceForge must be accessible during build
- No need to commit source tarballs to git
- Different versions can be built without changing the repo

---

## Required Secrets

No secrets required for basic builds.

For release creation, the workflow uses `GITHUB_TOKEN` which is automatically provided.

---

## Build Output

### Artifacts

Built packages are uploaded as artifacts (retained for 30 days):
- `packages-ubuntu-22.04`
- `packages-ubuntu-20.04`
- `packages-debian-12`
- `packages-fedora-39`
- `packages-opensuse-15.5`

### Release (if enabled)

When `create_release: true`:
- Creates tag `v{version}`
- Creates release with all .deb and .rpm files
- Includes installation instructions in release notes

---

## Build Time Estimates

| Stage | Time |
|-------|------|
| Container build | 2-3 minutes |
| Package build | 5-8 minutes |
| Upload artifacts | 1-2 minutes |
| **Total per distro** | **~10 minutes** |
| **All 5 distros (parallel)** | **~10 minutes** |

---

## Troubleshooting

### Build fails with "no space left on device"

GitHub runners have limited disk space. Add cleanup step:

```yaml
- name: Free disk space
  run: |
    sudo rm -rf /usr/share/dotnet
    sudo rm -rf /opt/ghc
    sudo rm -rf /usr/local/.ghcup
```

### SourceForge download fails

SourceForge may rate-limit or be temporarily unavailable. The build will fail. Retry later.

### Podman issues

The workflow uses Podman 4.9. If issues occur, try updating the version in the workflow.

---

## Cost Considerations

GitHub Actions free tier:
- 2000 minutes/month for public repos
- 500 MB artifact storage

**Estimated monthly usage:**
- 4 scheduled builds x 10 minutes = 40 minutes
- Manual builds as needed
- Well within free tier limits

---

## Recommended Workflow

1. **Test locally first** - Always test build locally before pushing
2. **Use manual builds for testing** - Don't wait for scheduled build
3. **Create releases sparingly** - Only for stable, tested versions
4. **Monitor artifact storage** - Delete old artifacts if approaching limit
