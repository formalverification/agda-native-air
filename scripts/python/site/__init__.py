"""
File: scripts/python/site/__init__.py

Description: The project site's build helpers (Issue #169): the MkDocs hook
  that carries the demo page into the site, the checks `make site-check` runs
  over the built tree, and the check that keeps requirements.txt and the Nix
  environment on the same versions.  The pages themselves are Markdown under
  docs/, rendered by MkDocs Material as mkdocs.yml configures; nothing here
  renders a page.
"""
