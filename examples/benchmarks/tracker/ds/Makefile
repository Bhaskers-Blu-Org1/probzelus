EX=tracker
ALGO=ds
NAME=tracker_ds

include ../../Makefile.common-config

CSV_FILES=perf.csv perf-step.csv mem-ideal.csv accuracy.csv

ZELUC+=-I ../trackerlib -I ../../../../owl

all: build

bench: bench_per_particles bench_per_steps bench_mem_ideal

include ../../Makefile.common-algo
