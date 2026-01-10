# UKB-RAP

This repository contains scripts, notebooks, and lightweight documentation for my **UK Biobank Research Analysis Platform (UKB-RAP)** work (DNAnexus cloud environment). It keeps my RAP workflow reproducible and centralizes project-specific code as analyses evolve.

## What this repo is for
- RAP-ready scripts for data handling, QC, and analysis
- Notebooks for exploratory analyses and validation checks
- Utilities to reduce repeated setup steps across RAP sessions
- Minimal documentation describing how each project is organized and run on RAP

## Current focus
**Rare-variant burden score portability by genetic distance (WGS v2):**  
Analyses examining how prediction performance of rare-variant burden scores varies with genetic distance from a reference group (e.g., distance from the EUR centroid in PC space).

## Repository structure (recommended)
- `startup/` — session setup helpers for RAP (SSH/Git, environment bootstrapping)
- `projects/` — project-specific code organized as:
  - `projects/<project_name>/scripts/`
  - `projects/<project_name>/notebooks/`
  - `projects/<project_name>/configs/`
  - `projects/<project_name>/docs/`
- `shared/` — reusable utilities across projects
- `results/` *(optional, usually not committed)* — local artifacts; typically upload outputs to DNAnexus project storage instead

## RAP workflow notes
RAP compute instances are ephemeral. Persistent items should be stored in DNAnexus project storage (e.g., using `dx upload`) and pulled into each session as needed.

Typical session:
1. Launch JupyterLab in the DNAnexus project
2. Run a bootstrap script to restore SSH keys and clone/update this repo
3. Execute project scripts/notebooks
4. Upload outputs back to the project (`dx upload`) for persistence

## Contact
Maintained by **Robel Alemu** (GitHub: `robelalemu01`).
