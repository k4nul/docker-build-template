# Security Policy

## Supported Versions

Security fixes target the current `main` branch until versioned releases are
published.

## Reporting a Vulnerability

Use GitHub private vulnerability reporting if it is enabled for the repository.
If it is not available, open a public issue with a short summary only and ask
for a private disclosure channel. Do not include registry credentials, tokens,
private image names, SBOMs with sensitive paths, or exploit details in public.

## Container Safety

Do not commit:

- registry credentials or auth files
- private image names or internal registry hosts
- generated image tarballs
- build cache directories
- environment files derived from `config/image.env.example`
