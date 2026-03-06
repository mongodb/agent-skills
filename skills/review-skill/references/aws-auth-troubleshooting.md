If AWS authentication fails, inspect the profile config to determine the auth
method and give the matching fix:

```bash
grep -A5 "\[profile <profile>\]" ~/.aws/config
```

| Config contains | Auth method | Fix |
|----------------|-------------|-----|
| `sso_start_url` or `sso_session` | SSO | `aws sso login --profile <profile>` |
| `role_arn` + `source_profile` | IAM role assumption | Refresh the source profile's credentials, then retry |
| `credential_process` | External tool | Run that tool directly to refresh |
| `aws_access_key_id` (in `~/.aws/credentials`) | Static IAM keys | Keys don't expire — verify `bedrock:InvokeModel` permission and model enablement in Bedrock console |

If the error mentions `ExpiredToken` or `ExpiredTokenException`, re-run
whichever process generated the temporary credentials (STS assume-role, SSO
login, etc.).
