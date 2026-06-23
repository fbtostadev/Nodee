# 🛡️ Contribution Guardrails for Nodee

**Purpose:** Prevent critical errors in git workflow and PR communication.

---

## ⚠️ Critical Rules

### Rule #1: Never Commit as AI Identity

**What:** Commits must ALWAYS be authored by the human developer, never by "Copilot", "AI", or generic bot identities.

**Why:** 
- Violates repository authenticity
- Pollutes contributor history
- Makes git blame/log confusing

**Guardrail:**

```bash
# BEFORE any commit or push, check:
git config user.name
git config user.email

# Must return human identity (e.g., "Jota Pe", "fbtostadev@...")
# If wrong, fix locally:
git config --local user.name "Your Name"
git config --local user.email "your@email.com"

# ❌ NEVER do this globally with AI identity
# ❌ NEVER commit on remote with wrong identity
```

---

### Rule #2: Never Use AI Slop in PRs or Commit Messages

**What is "AI Slop":**
- Generic templates: "This PR aims to enhance...", "comprehensive improvements"
- Vague descriptions: "refactor", "improve", "optimize"
- Non-specific language: "ensures best practices", "better user experience"
- Template phrases that don't match actual work

**Why:**
- Makes code review harder
- Reduces credibility in git history
- Confuses future maintainers
- Looks unmaintained

**Good Examples:**
```
✅ "feat: restore DragRevealMonitor from uxrefine/mvp branch
   
   Allows users to open Notch panel by dragging files near top of screen.
   Restored from uxrefine/mvp (commit f303d40) with updated dependencies."

✅ "fix: remap ColumnPath when file renamed via FSEvents
   
   Previously, rename/move operations could leave orphaned paths in 
   ColumnPath history. Now reconciles using updated URLs."
```

**Bad Examples:**
```
❌ "integrate uxrefine/mvp UX refinements into main"
❌ "add comprehensive improvements and optimizations"
❌ "This PR aims to harmonize branches divergent..."
```

**Checklist for PR Descriptions:**
- [ ] Specific, not generic (not "improve X", but "align Y height to Z")
- [ ] Explains WHY, not just WHAT
- [ ] Uses natural language (Portuguese or English, not templates)
- [ ] Includes actual commit refs, file paths, or technical details
- [ ] Sounds like a person writing it, not a template

---

## 🔄 Required Workflow

Never commit directly to `main` or `develop`. Always:

1. **Create feature branch** from `develop`
   ```bash
   git checkout develop
   git pull origin develop
   git checkout -b feat/describe-your-work
   ```

2. **Work locally** - make commits with human identity and specific messages

3. **Push to feature branch**
   ```bash
   git push origin feat/describe-your-work
   ```

4. **Create PR via GitHub UI** - with specific, non-generic description

5. **Await review + CI/CD** - never merge directly

6. **Merge via GitHub UI only** - never `git merge` directly into protected branches

---

## 🛑 Pre-Push Checklist

```bash
# Identity check
git config user.name                  # → Must be human
git config user.email                 # → Must be real

# Branch check
git branch                            # → Must be feature/*, not main/develop

# Commit message check
git log --oneline -5                  # → Specific, not generic

# Diff check
git diff develop..HEAD                # → Changes make sense?

# Status check
git status                            # → No uncommitted changes?
```

---

## 📋 Expected PR Description Format

```markdown
## What

[Describe exactly what was done - no generic templates]

## Why

[Explain the technical reason]

## How to Verify

[Specific steps, or "N/A"]

## Technical Notes

[Details: commit refs, limitations, decisions]
```

---

## 🚨 If You Violate These Rules

**Mistake #1: Committed as AI**
```bash
# Revert the commit
git revert <commit-hash>
# Or reset and recommit with correct identity
git reset HEAD~1
git config --local user.name "Your Name"
git commit -m "..."
```

**Mistake #2: Used AI Slop in PR**
```
# Edit PR description via GitHub UI
# Or close PR, rewrite description, create new PR
```

**Mistake #3: Direct Merge to main/develop**
```bash
# Revert immediately
git revert -m 1 <merge-commit-hash>
git push origin main
# Then create proper PR for review
```

---

**Last Updated:** 2026-06-23  
**Scope:** All Nodee repositories and contributors  
**Status:** ENFORCED
