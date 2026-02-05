# BibCop

**BibCop** is a lightweight, zero-dependency Perl script that patrols your bibliography to ensure quality and consistency.

Unlike `biber` or `bibtex`, which check for *syntax* errors, **BibCop checks for *manners***. It ensures your citations follow specific rules (e.g., "Years must be 4 digits") and checks the final output for broken data (e.g., `????` or `(n.d.)`).

### Key Features

* **Overleaf Native Integration:** Uses "Log Injection" to display errors and warnings directly in the **Overleaf side panel** (Red/Yellow badges).
* **Two Modes:**
* **Source Check (`.bib`):** Validates structure (e.g., "Title must use `{}` for acronyms").
* **Output Check (`.bbl`):** Validates the generated text (e.g., ensures no `????` or `(n.d.)` appears in the PDF).

* **Universal Support:** Works automatically with **BibTeX** (`.aux`) and **BibLaTeX/Biber** (`.bcf`).
* **Zero Dependencies:** Written in pure Perl. Runs anywhere `latexmk` runs.

## Installation

### 1. Add the files

Download `bibcop.pl` and `bibrules.conf` (or `bblrules.conf`)  and place them in your project's root directory (next to `main.tex`).

### 2. Update `.latexmkrc`

Add the following lines to your `.latexmkrc` file. (Create the file if it doesn't exist).

```perl
# .latexmkrc

# Choose Mode: 'bib' (Default) OR 'bbl'
$BibCopMode = 'bib';

# Load BibCop
do './bibcop.pl';
```

**That's it!** Next time you compile, BibCop will patrol your citations.

## Configuration

You can define rules in `bibrules.conf` (or `bblrules.conf`).
BibCop supports **Single-File Configuration**: you can write rules for both `.bib` and `.bbl` in the same file. The script automatically filters them based on the current mode.

### Syntax

`Target | Operator | Pattern | Level | Message`

* **Target**: The field name (e.g., `year`, `title`). Use `entry` for BBL checks.
* **Operator**: `missing`, `~` (regex match), `!~` (regex mismatch), `contains`.

### Example Configuration

```ini
# =======================================================================
#  SOURCE RULES (.bib mode)
#  Target: specific fields like 'year', 'title', 'author'
# =======================================================================

# Warn if Title has 2+ consecutive caps (e.g. "IEEE") not protected by {}
title    | ~       | [A-Z]{2,} | WARN  | Title has ALL CAPS. Use { } to protect.

# Error if Year is not exactly 4 digits
year     | !~      | ^\d{4}$   | ERROR | Year must be exactly 4 digits.

# Error if Author is missing
author   | missing | -         | ERROR | Author field is required.

# Warn if DOI contains the URL prefix (style preference)
doi      | contains| http      | WARN  | DOI should not include 'http' prefix.


# =======================================================================
#  OUTPUT RULES (.bbl mode)
#  Target: MUST be 'entry' (checks the rendered citation text)
# =======================================================================

# Error if the output contains placeholder question marks
entry    | contains | ????      | ERROR | Missing data detected (????) in output.

# Error if the date is missing (n.d.)
entry    | contains | (n.d.)    | ERROR | Missing date detected (n.d.).

# Warn if a paper is marked as 'submitted' (if not allowed)
entry    | contains | submitted | WARN  | Paper is marked as 'submitted'.

# Warn if a raw http link is found (should use \url{})
entry    | ~        | http[^s]  | WARN  | Raw http link found. Use \url{} or https.
```

## Modes

You can control what BibCop checks via the `$BibCopMode` variable in `.latexmkrc`.

| Mode | Description | Config File | Log Name |
| --- | --- | --- | --- |
| `'bib'` | **(Default)** Checks the source `.bib` files for structural issues. | `bibrules.conf` | `BibCop` |
| `'bbl'` | Checks the generated `.bbl` file for forbidden strings in the output. | `bblrules.conf` | `BibCopBBL` |

**Note:** If `bblrules.conf` is missing in `bbl` mode, BibCop will NOT fallback to `bibrules.conf` to avoid confusion. Please ensure the configuration file exists.

## Advanced Usage

### Custom Rule Filename

You can specify a custom rule file in `.latexmkrc`. This overrides the default filename.

```perl
$BibCheckRules = 'my_lab_rules.conf';
do './bibcop.pl';
```