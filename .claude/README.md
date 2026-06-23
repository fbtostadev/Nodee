# 📚 Claude Code & AI Agent Documentation Index

**Repository:** fbtostadev/Nodee  
**Last Updated:** 2026-06-23  
**Version:** 1.0

---

## 🎯 Quick Start

If you're an AI agent working on this repo:

1. **Read first:** `GUARDRAILS_FOR_CLAUDE_CODE.md` (this directory)
2. **Load config:** `railguards.json` or `railguards.yaml`
3. **Before any push:** Execute pre-push checklist
4. **Before any PR:** Validate description against guidelines

---

## 📂 Files in `.claude/`

### 1. `GUARDRAILS_FOR_CLAUDE_CODE.md`
**Format:** Markdown (human-readable)  
**Purpose:** Complete guide for AI agents  
**Sections:**
- Quick reference table
- Rule #1: Never AI identity
- Rule #2: No AI Slop  
- Rule #3: No direct merge
- Workflow state machine
- Pre-push checklist
- PR template guidelines
- Recovery instructions

**Use when:** You need human-readable explanation

---

### 2. `railguards.json`
**Format:** JSON (machine-parseable)  
**Purpose:** Structured configuration for code tools  
**Contents:**
- All guardrails (id, severity, violations, prevention)
- State machine definition (states, transitions, checks)
- Pre-push checklist items
- PR description rules
- Memory references

**Use when:** Programmatically checking rules or integrating with tools

**Example usage:**
```json
{
  "guardrails": [
    {
      "id": "auth_identity",
      "severity": "CRITICAL",
      "rule": "All commits must be authored by human developer..."
    }
  ]
}
```

---

### 3. `railguards.yaml`
**Format:** YAML (configuration syntax)  
**Purpose:** Configuration for deployment or tool setup  
**Contents:**
- Critical rules (rules, checks, violations)
- Workflow states with transitions
- Error recovery paths
- Pre-push checklist
- PR guidelines
- Documentation references

**Use when:** Setting up tool configuration or CI/CD checks

---

### 4. `README.md` (this file)
**Format:** Markdown navigation  
**Purpose:** Index and quick reference  

---

## 🔑 Three Critical Rules

### ❌ Rule #1: Never AI Identity
```
Check: git config user.name
Must be: Human (not "Copilot", "AI", "bot")
Fix: git config --local user.name "Your Name"
```

### ❌ Rule #2: No AI Slop
```
Check: PR description, commit message
Must be: Specific, technical, with context
Forbidden: "aims to", "comprehensive", "improve", etc.
```

### ❌ Rule #3: No Direct Merge
```
Check: Branch before push
Must be: feature/*, never main/develop
Method: Always use GitHub PR UI (never git merge CLI)
```

---

## 🔄 Workflow State Machine

```
START → BRANCH_CHECK → IDENTITY_CHECK → WORK_PHASE 
  → COMMIT_CHECK → PUSH → PR_CREATE → REVIEW → MERGE → END

Error states:
  BRANCH_CHECK fail → ERROR_BRANCH
  IDENTITY_CHECK fail → ERROR_IDENTITY
  COMMIT_CHECK fail → ERROR_SLOP (also PR_CREATE)
```

See `GUARDRAILS_FOR_CLAUDE_CODE.md` for full state diagram.

---

## ✅ Pre-Push Checklist

Execute before EVERY `git push`:

```bash
git config user.name           # Must be human
git config user.email          # Must be real
git branch                     # Must be feature/*, not main/develop
git log --oneline -5           # Must be specific (not generic)
git status                     # Must be clean
```

---

## 📋 PR Description Guidelines

### Sections (in order)
1. **What** (required) - Exact changes made
2. **Why** (required) - Technical reason
3. **How to Verify** (optional) - Test steps
4. **Technical Notes** (optional) - Context, refs, decisions

### Forbidden Phrases
❌ "aims to", "comprehensive", "improve", "optimize", "best practices", "ensures"

### Good Example
```
## What
Restore DragRevealMonitor from uxrefine/mvp (commit f303d40)

## Why
Allows users to open Notch panel by dragging files near screen top.
Feature was preserved in designapply merge.

## How to Verify
1. Drag file from Finder near top of screen
2. Notch should begin revealing after 0.3s dwell
3. Drop file to place it in current directory
```

---

## 🚨 Memory (Copilot Memory - Repository Scope)

These are stored in GitHub Copilot Memory and apply to ALL sessions:

```
Memory #1:
  Fact: Never author commits with AI identity; 
        always use human developer identity
  Scope: repository
  
Memory #2:
  Fact: Never use generic AI-generated language (AI Slop) 
        in PR descriptions, commit messages, or notices
  Scope: repository
  
Memory #3:
  Fact: Never perform direct merges into main or develop branches.
        Always use pull requests with review workflow.
  Scope: repository
```

---

## 📖 Documentation Hierarchy

```
Global (All sessions):
  └─ GitHub Copilot Memory (3 critical rules)
  
Repository:
  ├─ .github/CONTRIBUTION_GUARDRAILS.md (for humans)
  └─ .claude/ (for AI agents)
      ├─ railguards.json (machine-readable)
      ├─ railguards.yaml (config format)
      ├─ GUARDRAILS_FOR_CLAUDE_CODE.md (detailed guide)
      └─ README.md (this file)

Session:
  └─ ~/.copilot/session-state/.../RAILGUARDS.md (session workspace)
```

---

## 🔧 Integration with Claude Code

### Step 1: Load Configuration
```bash
# Load JSON into your config
cat .claude/railguards.json

# Or load YAML
cat .claude/railguards.yaml
```

### Step 2: Before Any Git Operation
Check the state machine:
1. Where are we? (current state)
2. Can we move to next state? (check preconditions)
3. Any violations? (check guardrails)

### Step 3: Before `git push`
Execute pre-push checklist:
- [ ] Identity is human
- [ ] Branch is feature/*, not protected
- [ ] Commits are specific (not generic)
- [ ] Status is clean

### Step 4: Before PR Creation
Validate description:
- [ ] Has "What" section (specific)
- [ ] Has "Why" section (technical reason)
- [ ] No forbidden phrases
- [ ] Sounds human-written, not templated

### Step 5: Before Merge
Use GitHub UI ONLY:
- ❌ Never `git merge`
- ❌ Never `gh pr merge`
- ✅ Always GitHub PR button

---

## ⚠️ Common Violations & Recovery

### Violation: Committed as AI
```bash
git revert <commit-hash>
git push origin
# OR
git reset HEAD~1
git config --local user.name "Your Name"
git commit -m "..."
```

### Violation: AI Slop in Commit
```bash
git commit --amend -m "Specific, detailed message"
git push origin --force-with-lease
```

### Violation: Direct Merge to main/develop
```bash
git revert -m 1 <merge-commit>
git push origin main
# Then create proper PR
```

---

## 📞 Questions?

- **For humans:** See `.github/CONTRIBUTION_GUARDRAILS.md`
- **For AI agents:** See `GUARDRAILS_FOR_CLAUDE_CODE.md`
- **For configuration:** See `railguards.json` or `railguards.yaml`
- **For memory facts:** Check GitHub Copilot Memory (repository scope)

---

**Status:** ENFORCED  
**Scope:** All sessions, all contributors, all AI agents  
**Version:** 1.0  
**Last Updated:** 2026-06-23
