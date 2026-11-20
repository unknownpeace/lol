## Summary

<!-- Briefly describe what this PR changes and why. -->

## Checklist

- [ ] Scripts use `#!/bin/sh` and remain compatible with BusyBox `ash` + OpenRC + `apk` (zero Docker / `opkg`).
- [ ] Passed `sh -n` syntax validation across all `.sh` files.
- [ ] Passed `shellcheck -S error` with zero errors.
- [ ] Verified pure LF (`\n`) line endings (no CRLF).
- [ ] Verified no tokens, passwords, personal domains, or test secrets are included.
- [ ] Updated documentation (`README.md` / `README.ru.md` / `ARCHITECTURE.md`) where applicable.
