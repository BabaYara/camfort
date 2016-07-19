# CamFort

## Installation & Building

### Using Stack

We recommend using Stack (http://www.haskellstack.org) to build Camfort. 

 1. Install Stack following the instructions here: http://docs.haskellstack.org/en/stable/README/#how-to-install
 3. Checkout the latest version of camfort
 5. Build using Stack

```
git clone git@github.com:camfort/camfort.git
cd camfort
stack setup
stack build
stack install      # install binary
stack exec camfort # run camfort
```

If you want to build a version for profiling then you can use

```
stack build --enable-executable-profiling --enable-library-profiling --ghc-options="-fprof-auto -rtsopts"
```

Please note that at this time we have been unable to compile Camfort on Windows due to a problem with the hmatrix dependency. 

### Using Cabal

Cabal does not automatically install the build tools. If you wonder why
checkout haskell/cabal#220.

```
$ cabal install alex happy
```

Install the native packages needed for `hmatrix` dependency

```
sudo apt-get install libgsl0-dev liblapack-dev libatlas-base-dev
```

### For general usage

```
$ cabal install camfort
```

### For development

```
$ cabal sandbox init
$ cabal install --only-dependencies
$ cabal exec bash
```

This spawns a new shell with only the packages within the sandbox available.

```
$ ghc Main.hs -o camfort
```

This generates a camfort executable in the root directory using only the
packages in the sandbox and none of ~/.cabal or system Haskell packages.

## Usage

```
CamFort 0.801 - Cambridge Fortran Infrastructure.
Usage: camfort <MODE> <INPUT> [OUTPUT] [OPTIONS...]
Refactor functions:
	common         	 [common block elimination] 
	commonArg      	 [common block elimination (to parameter passing)] 
	equivalence    	 [equivalence elimination] 
	dataType       	 [derived data type introduction] 
	dead           	 [dead-code elimination] 

Analysis functions:
	asts           	 [blank analysis, outputs analysis files with AST information] 
	lva            	 [live-variable analysis] 
	loops          	 [loop information] 
	count          	 [count variable declarations] 
	ast            	 [print the raw AST -- for development purposes] 
	stencils-check 	 [stencil spec checking] 
	stencils-infer 	 [stencil spec inference] 
	stencils-synth 	 [stencil spec synthesis] 
	units-suggest  	 [suggest variables to annotate for units-of-measure for maximum coverage] 
	units-check    	 [unit-of-measure checking] 
	units-infer    	 [unit-of-measure inference] 
	units-synth    	 [unit-of-measure synthesise specs.] 

Options:
  -v, -?    --version                    show version number
  -e FILES  --exclude=FILES              files to exclude (comma separated list, no spaces)
  -s ID     --units-solver=ID            units-of-measure solver. ID = Custom or LAPACK
  -l ID     --units-literals=ID          units-of-measure literals mode. ID = Unitless, Poly, or Mixed
  -m ID     --stencil-inference-mode=ID  stencil specification inference mode. ID = Do, Assign, or Both
```

### Troubleshooting
 Sometimes MacOSX has problems with GHC and libiconv. Some of the techniques here are useful: http://blog.omega-prime.co.uk/?p=96
