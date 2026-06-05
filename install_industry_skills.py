# Databricks notebook source
# MAGIC %md
# MAGIC # Install Databricks Industry Skills
# MAGIC
# MAGIC Install Genie Code skill families from
# MAGIC [`guanjieshen/databricks-industry-skills`](https://github.com/guanjieshen/databricks-industry-skills)
# MAGIC into this workspace — **pick the data source(s) you want and install all of their skills**
# MAGIC (e.g. all of Maximo). No clone or CLI setup needed; skills are pulled straight from GitHub.
# MAGIC
# MAGIC **Nothing installs by default.** Select one or more families in the `FAMILIES` widget first.
# MAGIC
# MAGIC ### How to use
# MAGIC 1. Run **Cell: Configure** — pick `FAMILIES` (e.g. `maximo`) and the install `SCOPE` in the widgets.
# MAGIC 2. Run **Cell: Install** — installs every skill in each selected family.
# MAGIC 3. Run **Cell: Verify** to confirm what landed.
# MAGIC
# MAGIC After installing, open a **new** Genie Code chat — skills load when their description matches your prompt.

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell: Configure
# MAGIC Pick the data-source family/families, install scope, and source ref.

# COMMAND ----------

import base64
import posixpath
import json
import urllib.request

from databricks.sdk import WorkspaceClient
from databricks.sdk.service.workspace import ImportFormat

# -- Source repo -------------------------------------------------------------
GITHUB_OWNER = "guanjieshen"
GITHUB_REPO = "databricks-industry-skills"

# Top-level dirs that hold skills but are NOT installable families.
EXCLUDE_DIRS = {"_template", "_authoring"}


def _github_api(url):
    """Fetch JSON from the GitHub API. Returns parsed JSON, or None on error."""
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github.v3+json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f"  WARN GitHub API error: {e}")
        return None


def _download(url):
    """Download raw file bytes. Returns bytes on success, None on failure."""
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            return resp.read()
    except Exception:
        return None


def _tree(ref):
    """Full recursive git tree of the repo at `ref` (set of blob paths)."""
    data = _github_api(
        f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/git/trees/{ref}?recursive=1"
    )
    if not data:
        return set()
    return {item["path"] for item in data.get("tree", []) if item["type"] == "blob"}


def _discover_families(files):
    """A family = any top-level dir containing a <skill>/SKILL.md (minus EXCLUDE_DIRS)."""
    fams = set()
    for p in files:
        parts = p.split("/")
        if len(parts) >= 3 and parts[-1] == "SKILL.md":
            fams.add(parts[0])
    return sorted(f for f in fams if f not in EXCLUDE_DIRS)


def _skills_in_family(files, family):
    """All skill directory names under a family (each contains a SKILL.md)."""
    prefix = f"{family}/"
    return sorted({
        p[len(prefix):].split("/")[0]
        for p in files
        if p.startswith(prefix) and p.endswith("/SKILL.md")
    })


# Use the current ref (default "main") so the FAMILIES widget reflects the repo.
_boot_ref = "main"
try:
    _boot_ref = dbutils.widgets.get("GITHUB_REF") or "main"
except Exception:
    pass

_files = _tree(_boot_ref)
_families = _discover_families(_files)

dbutils.widgets.text("GITHUB_REF", "main", "1. Source branch / tag")
dbutils.widgets.dropdown("SCOPE", "user", ["user", "workspace"], "2. Install scope")
dbutils.widgets.multiselect(
    "FAMILIES", _families[0] if _families else "", _families or [""], "3. Data source(s) to install"
)

w = WorkspaceClient()
username = w.current_user.me().user_name

SCOPE = dbutils.widgets.get("SCOPE")
SKILLS_PATH = (
    "/Workspace/.assistant/skills"
    if SCOPE == "workspace"
    else f"/Workspace/Users/{username}/.assistant/skills"
)

print(f"Repo           : {GITHUB_OWNER}/{GITHUB_REPO} @ {_boot_ref}")
print(f"Families found : {', '.join(_families) or '(none — check GITHUB_REF)'}")
for fam in _families:
    print(f"   - {fam}: {', '.join(_skills_in_family(_files, fam))}")
print(f"\nInstall scope  : {SCOPE}  ->  {SKILLS_PATH}")
print("\nNext: select FAMILIES in the widget above, then run the Install cell.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell: Install
# MAGIC Installs every skill in each selected family. **Installs nothing if no family is selected.**

# COMMAND ----------

def _upload(w, workspace_path, content):
    w.workspace.mkdirs(posixpath.dirname(workspace_path))
    w.workspace.import_(
        path=workspace_path,
        content=base64.b64encode(content).decode(),
        format=ImportFormat.AUTO,
        overwrite=True,
    )


def _install_skill(w, family, name, files, ref, skills_path):
    """Upload a skill's SKILL.md + every sibling blob under {family}/{name}/ (incl. scripts/)."""
    prefix = f"{family}/{name}/"
    members = sorted(p for p in files if p.startswith(prefix))
    raw_base = f"https://raw.githubusercontent.com/{GITHUB_OWNER}/{GITHUB_REPO}/{ref}"
    dest_root = f"{skills_path}/{name}"
    uploaded = 0
    for path in members:
        rel = path[len(prefix):]               # e.g. "scripts/apply_uc_comments.py"
        data = _download(f"{raw_base}/{path}")
        if data is None:
            print(f"    WARN could not download {path}")
            continue
        _upload(w, f"{dest_root}/{rel}", data)
        uploaded += 1
    print(f"    OK {name} ({uploaded} file{'s' if uploaded != 1 else ''})")
    return uploaded > 0


REF = dbutils.widgets.get("GITHUB_REF") or "main"
selected = [f for f in dbutils.widgets.get("FAMILIES").split(",") if f]

if not selected:
    print("No family selected — installing nothing.")
    print("Pick one or more families in the FAMILIES widget, then re-run this cell.")
else:
    files = _tree(REF)
    installed = failed = 0
    for family in selected:
        skills = _skills_in_family(files, family)
        if not skills:
            print(f"\n{family}: no skills found — skipping.")
            continue
        print(f"\nInstalling '{family}' ({len(skills)} skills) into {SKILLS_PATH}")
        for name in skills:
            if _install_skill(w, family, name, files, REF, SKILLS_PATH):
                installed += 1
            else:
                failed += 1
    print(f"\nDone. {installed} installed, {failed} failed.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell: Verify
# MAGIC Lists the skills currently installed at the target path.

# COMMAND ----------

from databricks.sdk import WorkspaceClient

w = WorkspaceClient()
username = w.current_user.me().user_name
scope = dbutils.widgets.get("SCOPE")
skills_path = (
    "/Workspace/.assistant/skills"
    if scope == "workspace"
    else f"/Workspace/Users/{username}/.assistant/skills"
)

try:
    entries = list(w.workspace.list(skills_path))
    subdirs = sorted(
        e.path.split("/")[-1]
        for e in entries
        if str(e.object_type) == "ObjectType.DIRECTORY"
    )
    if subdirs:
        print(f"Found {len(subdirs)} skill(s) in {skills_path}:\n")
        for name in subdirs:
            print(f"  {name}")
    else:
        print(f"No skills found in {skills_path}.")
except Exception as e:
    print(f"Could not list skills: {e}")
