# 🛡️ Nodee Contribution Guardrails & State Machine

**For: Claude Code, future AI agents, and contributors**  
**Version:** 1.0  
**Created:** 2026-06-23  
**Scope:** fbtostadev/Nodee  
**Status:** ENFORCED

---

## 📋 Quick Reference

| Rule | Severity | Check Before | Recovery |
|------|----------|--------------|----------|
| Never AI identity | 🔴 CRITICAL | `git push` | `git config --local user.name` |
| No AI Slop | 🔴 CRITICAL | PR creation | Rewrite with specifics |
| No direct merge | 🔴 CRITICAL | `git push` to main/develop | Use PR workflow |

---

## ⚠️ Rule #1: Never Author as AI Identity

### What This Means
All commits MUST be authored by the human developer, never by "Copilot", "AI", "bot", or any non-human identity.

### Why
- Violates repository authenticity
- Pollutes contributor history on GitHub
- Makes git blame confusing for future maintainers

### Check Command
```bash
git config user.name
git config user.email
```

**Must Return:** Human name and real email (e.g., "Jota Pe", "jotape@...")  
**Must NOT Return:** "Copilot", "AI", "bot", any generic AI identity

### Prevention
```bash
# BEFORE git push, always check:
git config user.name

# If wrong, fix locally:
git config --local user.name "Your Name"
git config --local user.email "your@email.com"

# ❌ NEVER do this globally with AI identity
# ❌ NEVER --global flag with non-human name
```

### If Violated
```bash
# Revert the commit
git revert <commit-hash>
git push origin

# OR reset and re-commit
git reset HEAD~1
git config --local user.name "Your Name"
git commit -m "..."
git push origin
```

---

## ⚠️ Rule #2: No AI Slop in PRs or Commits

### What is "AI Slop"
Generic, template-like language that doesn't reflect actual work:

**Examples of AI Slop:**
```
❌ "This PR aims to enhance the system..."
❌ "Add comprehensive improvements and optimizations"
❌ "Improve user experience and refactor code"
❌ "Ensures best practices and allows better..."
```

**Examples of Good Language:**
```
✅ "feat: restore DragRevealMonitor from uxrefine/mvp
   
   Allows users to open Notch by dragging files near screen top.
   Restored from uxrefine/mvp (commit f303d40) with updated Notch geometry."

✅ "fix: remap ColumnPath when FSEvents detects file rename
   
   Previously, rename/move operations could leave orphaned paths in history.
   Now reconciles using updated file URLs via FSEvents handler."
```

### Why This Matters
- Vague descriptions confuse code reviewers
- Makes git history unhelpful for future maintainers
- Reduces credibility of contributions
- Looks like "autopilot" commits, not intentional work

### Checklist: Is This AI Slop?

- [ ] Description is specific to THIS work (not generic)
- [ ] Explains technical reason WHY (not just WHAT)
- [ ] Uses natural language (Portuguese or English, not templates)
- [ ] Includes actual file paths, commit refs, or numbers
- [ ] Avoids forbidden phrases: "aims to", "comprehensive", "improve", "optimize", "best practices", "ensures"
- [ ] Sounds like a person wrote it, not a template

### Prevention
```
BEFORE commit or PR:
  → Describe EXACTLY what you did
  → Explain WHY it matters technically
  → Include specific details (file names, refs, context)
  → Avoid generic template phrases
```

### If Violated (Commit Message)
```bash
# Amend the commit
git commit --amend -m "Specific, non-generic message"
git push origin --force-with-lease  # only if not yet on main/develop
```

### If Violated (PR Description)
```
Option 1: Edit PR description via GitHub UI
Option 2: Close PR, rewrite, create new PR
```

---

## ⚠️ Rule #3: Never Direct Merge to main/develop

### What This Means
NEVER use `git merge` directly on `main` or `develop` branches.  
ALWAYS use the PR workflow via GitHub UI.

### Violations
```bash
❌ git checkout main; git merge feature-branch
❌ git checkout develop; git merge feature-branch
❌ Any direct merge to protected branches
```

### Correct Workflow
```bash
# 1. Create feature branch
git checkout develop
git pull origin develop
git checkout -b feat/your-work

# 2. Work locally, commit
git add ...
git commit -m "specific message"

# 3. Push feature branch (NOT main/develop)
git push origin feat/your-work

# 4. Create PR via GitHub UI
# → Title: Specific (no AI Slop)
# → Description: Detailed (no templates)

# 5. Await review + CI/CD
# → Code review
# → Automated tests pass
# → All checks green

# 6. Merge via GitHub UI button
# → NEVER use: git merge, gh pr merge --admin, etc.
# → ALWAYS use: GitHub "Merge" button
```

### If Violated
```bash
# IMMEDIATELY revert
git revert -m 1 <merge-commit-hash>
git push origin main

# Then create proper PR to re-do the work
```

---

## 🔄 Complete Workflow State Machine

```
START
  ↓
┌─────────────────────────────────────┐
│ BRANCH_CHECK                        │
│ (Are you on main or develop?)       │
└─────────────────────────────────────┘
  YES → ERROR_BRANCH (STOP!)
  NO ↓
┌─────────────────────────────────────┐
│ IDENTITY_CHECK                      │
│ (Is git user.name human?)           │
└─────────────────────────────────────┘
  NO → ERROR_IDENTITY (STOP!)
  YES ↓
┌─────────────────────────────────────┐
│ WORK_PHASE                          │
│ (Make changes in feature branch)    │
└─────────────────────────────────────┘
  ↓
┌─────────────────────────────────────┐
│ COMMIT_CHECK                        │
│ (Is message specific, not AI Slop?) │
└─────────────────────────────────────┘
  NO → ERROR_SLOP (STOP!)
  YES ↓
┌─────────────────────────────────────┐
│ PUSH                                │
│ (git push origin feature-branch)    │
└─────────────────────────────────────┘
  ↓
┌─────────────────────────────────────┐
│ PR_CREATE                           │
│ (GitHub UI, check description)      │
└─────────────────────────────────────┘
  NO good description → ERROR_SLOP (STOP!)
  YES ↓
┌─────────────────────────────────────┐
│ REVIEW                              │
│ (Code review + CI/CD checks)        │
└─────────────────────────────────────┘
  ↓
┌─────────────────────────────────────┐
│ MERGE                               │
│ (GitHub UI button ONLY)             │
└─────────────────────────────────────┘
  ↓
  END ✅
```

---

## 🛑 Pre-Push Checklist

**Execute ALWAYS before `git push`:**

```bash
# 1. Identity check
git config user.name
git config user.email
# → Must be human (not AI/Copilot)

# 2. Branch check
git branch
# → Must be feature/*, never main or develop

# 3. Commit message check
git log --oneline -5
# → Must be specific, not generic template

# 4. Status check
git status
# → Must be clean (no uncommitted changes)

# 5. Diff review
git diff develop..HEAD
# → Changes should make sense
```

---

## 📝 PR Description Template

Use this structure (NO generic templates):

```markdown
## What

[Describe exactly what was done - specific, not "improve X" but details like "align Notch height to X pixels"]

## Why

[Technical reason - "to fix FSEvents reconciliation" not "best practices"]

## How to Verify

[Specific steps to test, or "N/A" if not applicable]

## Technical Notes

[Optional: commit refs, limitations, design decisions]
```

**Forbidden Phrases:**
- "aims to"
- "comprehensive"
- "improve"
- "optimize"
- "refactor" (as standalone, ok with context)
- "best practices"
- "ensures"
- "allows the user"

---

## 📚 Documentation Files

| File | Purpose | Scope |
|------|---------|-------|
| `.github/CONTRIBUTION_GUARDRAILS.md` | Repository guide for all contributors | Public |
| `.claude/railguards.json` | Machine-readable (Claude Code import) | Dev tools |
| `.claude/railguards.yaml` | Configuration format (other tools) | Dev tools |
| `~/.copilot/session-state/.../RAILGUARDS.md` | Session workspace copy | Session only |

---

## 🔗 Copilot Memory References

These facts are stored in Copilot Memory (repository scope, all sessions):

1. **Never author commits with AI identity**
   - Use human developer identity always
   - Check `git config user.name` before every push
   
2. **Never use generic AI-generated language (AI Slop)**
   - PR descriptions and commits must be specific
   - Include technical context, file paths, commit refs
   - Avoid template phrases
   
3. **Never perform direct merges into main/develop**
   - Always use feature branch → PR workflow
   - Merge via GitHub UI only (never CLI)
   - Protected branches require review + CI/CD

---

## ✅ How to Use These Guardrails

### For Human Contributors
1. Read this document before committing
2. Follow state machine
3. Execute pre-push checklist
4. Create PR with specific description
5. Merge via GitHub UI

### For Claude Code / AI Agents
1. Load `railguards.json` or `railguards.yaml`
2. Check pre-push checklist before any `git push`
3. Verify identity = human (never author as self)
4. Validate PR description against forbidden phrases
5. Never execute direct merge commands
6. Always route to GitHub UI for merges

### If You Violate Rules
1. Identify which rule was broken (see error recovery sections above)
2. Execute recovery command immediately
3. Document what went wrong
4. Never push to main/develop directly again

---

**Last Updated:** 2026-06-23  
**Version:** 1.0  
**Status:** ENFORCED ACROSS ALL SESSIONS  
**Audience:** fbtostadev, Copilot agents, all future contributors
