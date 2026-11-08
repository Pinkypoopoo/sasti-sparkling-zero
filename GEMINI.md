# Sasti Sparkling Zero - Architecture & Karpathy Rules
1. List assumptions first; if anything is unclear, stop and ask before writing code.
2. Write the minimum code required; keep modules compact and focused.
3. Touch only the lines and files the task requires; never truncate working logic.
4. Every change must pass `bash verify.sh` (`godot --path . --headless --quit-after 10`) with zero parse or runtime errors.
