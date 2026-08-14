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

The pinned Intel base also contains operating-system and language packages with
published advisories. Some critical Ubuntu matches are attached to the
`linux-libc-dev` header package; containers use the host kernel and do not run a
kernel from that package. This does not make all inherited findings irrelevant.
The initial 2026-08-13 Trivy scan reported 18 critical and 228 high matches:
16 critical matches were in `linux-libc-dev`, and two were the version-matched
vLLM authentication CVE whose backport is documented and regression-tested
above. Keep the endpoint private, review current scan output, and rebase onto a
newer Intel image when the XPU/MTP patch set has been revalidated there.

Report a suspected vulnerability privately to the repository owner through
GitHub's private vulnerability reporting feature. Do not include real API
keys, prompts, model data, or private network details in a public issue.
