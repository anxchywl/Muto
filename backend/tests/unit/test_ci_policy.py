from __future__ import annotations

import re
from pathlib import Path

WORKFLOWS = Path(__file__).parents[3] / ".github" / "workflows"
ACTION_REFERENCE = re.compile(r"uses:\s+[^\s]+@([^\s#]+)")
COMMIT_SHA = re.compile(r"^[0-9a-f]{40}$")


def test_every_action_is_pinned_to_a_commit() -> None:
    for workflow in WORKFLOWS.glob("*.yml"):
        references = ACTION_REFERENCE.findall(workflow.read_text())
        assert references
        assert all(COMMIT_SHA.fullmatch(reference) for reference in references)


def test_scanner_downloads_are_verified() -> None:
    workflow = (WORKFLOWS / "ci.yml").read_text()
    assert workflow.count("sha256sum --check") == 2


def test_deployment_requires_a_runtime_change() -> None:
    workflow = (WORKFLOWS / "ci.yml").read_text()
    assert "needs.changes.outputs.backend == 'true' || " in workflow
    assert "needs.changes.outputs.deploy == 'true')" in workflow


def test_release_requires_default_branch_and_source_verification() -> None:
    workflow = (WORKFLOWS / "release.yml").read_text()
    assert 'git merge-base --is-ancestor "$GITHUB_SHA"' in workflow
    assert "run: ./scripts/verify.sh" in workflow
