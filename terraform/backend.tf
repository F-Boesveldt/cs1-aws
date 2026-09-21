# Using local state (not a remote S3 backend). AWS Academy's identity-based
# policy denies S3 object-level actions for this account (confirmed by two
# separate 403/explicit-deny errors during setup), so a remote backend
# isn't workable here. State is kept locally in terraform.tfstate, already
# excluded from Git via .gitignore. Since terraform apply already has to
# run locally each session due to Academy's rotating credentials (see the
# CI/CD note elsewhere), a shared remote backend provided little practical
# benefit in this environment anyway.
