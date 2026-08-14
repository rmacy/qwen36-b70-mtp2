# Security

The supplied `run.sh` binds the API to `127.0.0.1` by default. Set `API_KEY` to
enable vLLM's bearer-token authentication, and put an authenticated gateway in
front of the service if remote clients need access. Do not publish port 8000
directly to an untrusted network.

## CVE-2026-48746 backport

Intel's pinned base contains a vLLM revision older than 0.22.0 and is therefore
version-matched by scanners to CVE-2026-48746, an API-key authentication bypass.
This image backports the complete two-line upstream fix from vLLM pull request
43426: authentication now reads the ASGI scope path directly rather than
reconstructing it through a caller-controlled `Host` header.

`tests/verify_auth_backport.py` verifies that the vulnerable reconstruction is
absent, then exercises both an ordinary unauthenticated request and the
malicious-Host shape. Both must return HTTP 401 when vLLM's built-in API key is
configured. Version-only scanners may continue to report the CVE because the
Intel package version remains unchanged.

## Scan scope

Before the initial release, the complete source, Git objects, image
configuration, image history, and container filesystem were scanned for
secrets and private deployment identifiers. No secrets were found. The
repository and runtime contain no Qwen checkpoint weights; one small
`compressed_tensors` Hadamard-transform data file is inherited from the base
Python environment.

Release 0.1.2 pins Ubuntu's fixed `linux-libc-dev` 6.8.0-137.137 package on top
of the Intel base. A Trivy 0.73.0 scan of the clean release candidate on
2026-08-13 found zero secrets, two critical matches, and 68 high matches. Both
critical matches are duplicate version-based detections of CVE-2026-48746; the
backport and exploit regression test are documented above. The image still
contains inherited packages with published high-severity advisories. Keep the
endpoint private, review current scan output, and rebase onto a newer Intel
image when the XPU/MTP patch set has been revalidated there.

Report a suspected vulnerability privately to the repository owner through
GitHub's private vulnerability reporting feature. Do not include real API
keys, prompts, model data, or private network details in a public issue.
