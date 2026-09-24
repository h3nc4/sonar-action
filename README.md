# sonar-action

Gives every branch its own SonarQube project, so a pull request can be analysed without
overwriting the history your default branch built.

SonarQube Community Edition analyses one branch per project. Point CI at one project and every
pull request overwrites main's measures, so the dashboard describes whichever branch scanned
last. The usual answer is to scan only on main, which is the same as having no gate
where it matters. This action takes the other route: main keeps the official project, every
other ref and every pull request scans under a throwaway named after it, and the throwaway is
deleted once it passes.

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0
- uses: h3nc4/sonar-action@v1
  with:
    host-url: ${{ vars.SONAR_HOST_URL }}
    token: ${{ secrets.SONAR_TOKEN }}
```

The official project key comes from `sonar.projectKey` in `sonar-project.properties`, the file
the scanner already reads, so nothing has to be told twice what the project is called. A pull
request then scans `<key>-pr-<number>`, another branch scans `<key>-ref-<branch>`, and the
default branch scans `<key>` itself.

## The scan stays in your repository

This action sets `SONAR_PROJECT_KEY` to the project a run writes to. It does not run the
scanner: it hands the work to `./scripts/sonar.sh`, adding `-d` when the project is a throwaway
to delete afterwards.

A scan is worth running before a push as well as in CI, from a pre-push hook or by hand on a
workstation, and `scripts/sonar.sh` is what those two reach for. Moving the invocation in here
would leave two implementations of one scan, and the day they disagree is the day CI stops
testing what developers run. So the script keeps the scanner flags, the memory caps and the
per-developer project a workstation run uses, and this action supplies the project name CI has
to choose.

A script it calls needs to accept `-d` and honour `SONAR_PROJECT_KEY`. That is the whole
contract.

A repository whose scan sits in the dev container every repository shares, rather than in its
own tree, names that image in `image` and the path inside it in `script`. The action copies the
file out and runs it on the runner, so nothing about the scan changes. Pair it with
`h3nc4/dev-image-action`, whose `image` output resolves the pinned or candidate image:

```yaml
- id: dev
  uses: h3nc4/dev-image-action@v2
- uses: h3nc4/sonar-action@v1
  with:
    token: ${{ secrets.SONAR_TOKEN }}
    image: ${{ steps.dev.outputs.image }}
    script: /usr/local/bin/sonar
```

## Quality gates

A gate belongs to a project, and a project created on the fly by a scan inherits the server
default. Pass `gate` when a project needs a different one and the action exports `SONAR_GATE`
for the script to select.

Leaving `gate` empty is usually right. A repository held to a non-default gate needs the same
gate in its pre-push run, so the name belongs in the script's own default, where both paths
read it. The input overrides that from a workflow.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `token` | required | Scanner token, exported as `SONAR_TOKEN`. |
| `host-url` | `""` | SonarQube to scan against, exported as `SONAR_HOST_URL`. Empty leaves the script's default. |
| `script` | `./scripts/sonar.sh` | The scan itself. Must accept `-d` and honour `SONAR_PROJECT_KEY`. A path inside `image` when that is set. |
| `image` | `""` | Image the scan is copied out of, for a scan that lives in the dev container rather than the tree. |
| `properties-file` | `sonar-project.properties` | Where the official project key is read. |
| `key` | `""` | Official project key, overriding the properties file. |
| `gate` | `""` | Quality gate, exported as `SONAR_GATE`. Empty leaves it to the script. |
| `default-branch` | the repository's | Branch that writes the official project. |

## Outputs

| Output | Meaning |
| --- | --- |
| `project-key` | Project the scan wrote to. |
| `throwaway` | Whether that project was a throwaway, deleted once the scan passed. |

## Server permissions

The token's account must be able to provision projects, and to administer the ones it creates,
or a throwaway can be neither made nor deleted. On a self-hosted SonarQube that is a technical
account in a group holding the `scan` and `provisioning` global permissions, with `admin` on new
projects through the default permission template.

## Licence

BSD-2-Clause. See [LICENSE](LICENSE).
