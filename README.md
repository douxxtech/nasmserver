> [!CAUTION]
> This branch is not maintained anymore.

This folder contains the source code of the NASM Server running on `nasmserver.douxx.tech`.  
A proper git repository will be set up eventually, this (nasmserver.douxx.tech/source.zip) is a temporary distribution method.

The entry file is `program.asm`, macros/utils are in `macros/`.  
The `old` branch contains pre-refactor files. It is also not maintainted anymore

I've been learning NASM for 4 days, so errors may exist. feel free to report them via [douxx@douxx.xyz](mailto:douxx@douxx.xyz) or through wherever you found this.

See `LICENSE` for usage terms.

### Compilation
Requires: `nasm gcc binutils`
```bash
bash buildasm.sh program.asm
```

Expected output:
```plaintext
Built executable: program
```