# Python Git mirrors — 2026-10-16

The user explicitly authorized configuring and pushing this Python repository
to the five destinations below. This supersedes the audit's earlier no-push
boundary. Scope is `D:/MyNewProjects/qfli_python` only; no shared-core or sibling
repository is pushed by this operation.

| Remote | Fetch/push URL |
| --- | --- |
| `origin` (GitHub) | `https://github.com/azurekiln2333/qflistudio-python.git` |
| `gitee` | `https://gitee.com/azurekiln/qflistudio-python.git` |
| `gitlab` | `https://gitlab.com/azurekiln-team/qflistudio-python.git` |
| `gitcode` | `https://gitcode.com/azurekiln/qflistudio-python.git` |
| `cnb` | `https://cnb.cool/azurekiln/qflistudio-python` |

## Local configuration

`origin` fetches from GitHub and has all five URLs as explicit push URLs.
The four named secondary remotes permit independent inspection/retry.
Repository-local `remote.pushDefault=origin` and `push.default=simple` make
plain `git push` send the current tracked branch to all five destinations.
Both `main` and `release/python-storefront-20261015` track the corresponding
GitHub `origin` branch.

Verify the local, untracked Git configuration with:

```powershell
git remote -v
git remote get-url --push --all origin
git config --local --get remote.pushDefault
```

## Initial publication

All five destinations returned no HEAD or branch refs during the initial
`git ls-remote --symref` checks. Local `main` at `5e681bf` is an ancestor of
release HEAD `584ff57` (16 later commits). Fast-forward local `main` to the
latest release/documentation commit and publish both branches without force,
then compare both remote branch OIDs with that commit on every platform.

The publication includes this configuration record and its independent review.
Existing uncommitted OHOS icons/startup/routes/AgreementReader and local agent
configuration remain outside the commits. Existing signing configuration and
history remain unchanged; the signing fields are DevEco ciphertext and no
credential/key file is tracked. Device acceptance gates remain open separately.
