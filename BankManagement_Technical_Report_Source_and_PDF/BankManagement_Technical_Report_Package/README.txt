BankManagement - Database and Software Architecture Report
===========================================================

Files
-----
1. BankManagement_Technical_Report.tex  Editable LaTeX source
2. BankManagement_Technical_Report.pdf  Compiled 54-page report

Before submission
-----------------
Open the .tex file and complete the Student, Instructor, and Date fields on the title page.

Compile
-------
Run the following command twice so the table of contents, references, lists, and final page number are resolved:

    pdflatex -interaction=nonstopmode BankManagement_Technical_Report.tex
    pdflatex -interaction=nonstopmode BankManagement_Technical_Report.tex

The source uses standard TeX Live packages, including tikz, tcolorbox, longtable, listings, pdflscape, and hyperref.

Main revisions in this edition
------------------------------
- Formal project-report wording instead of prompt-like or agent-like narration.
- Repository-level proof that no ORM is used.
- Direct comparison between the mssql driver and an ORM.
- Explicit evidence from package.json, db.js, procedure.js, route files, and T-SQL procedures.
- Improved SQL-injection explanation, including typed request.input binding and server-owned report whitelists.
- Rebuilt wide tables, API inventories, ER figures, lifecycle diagrams, and long identifiers to prevent clipping and overlap.
- Visual verification of all 54 rendered pages.
