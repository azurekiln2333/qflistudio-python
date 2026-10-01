# Backend Development Guidelines

> Best practices for backend development in this project.

---

## Overview

This directory contains guidelines for backend development. Fill in each file with your project's specific conventions.

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Native Python Runtime](./native-python-runtime.md) | C VM, file I/O, MethodChannel and verification contracts | Implemented |
| [Python FFI](./python-ffi.md) | Desktop/Apple packaging, C ownership and Windows reader contract | Implemented |
| [Android Build](./android-build.md) | NDK, JVM budgets, APK and emulator verification | Implemented |
| [Directory Structure](./directory-structure.md) | Module organization and file layout | To fill |
| [Database Guidelines](./database-guidelines.md) | ORM patterns, queries, migrations | To fill |
| [Error Handling](./error-handling.md) | Error types, handling strategies | To fill |
| [Quality Guidelines](./quality-guidelines.md) | Code standards, forbidden patterns | To fill |
| [Logging Guidelines](./logging-guidelines.md) | Structured logging, log levels | To fill |

---

## How to Fill These Guidelines

For each guideline file:

1. Document your project's **actual conventions** (not ideals)
2. Include **code examples** from your codebase
3. List **forbidden patterns** and why
4. Add **common mistakes** your team has made

The goal is to help AI assistants and new team members understand how YOUR project works.

---

**Language**: All documentation should be written in **English**.

## Pre-Development Checklist

Read `native-python-runtime.md` for changes in native C/C++, ArkTS bridges,
or the Python runner. Read `../frontend/python-workflow.md` when UI is involved.
Read `python-ffi.md` for FFI, desktop/Apple packaging and Windows port changes.

## Quality Check

Follow the native runtime spec's test section: real host C VM, Flutter checks,
ARM64 build/dependency scan, ArkTS copy hashes, signed HAP and device self-check.
Record missing device evidence explicitly and keep unfinished tasks active.
