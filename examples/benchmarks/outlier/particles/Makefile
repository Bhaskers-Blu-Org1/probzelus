EX=outlier
ALGO=particles
NAME=outlier_particles

include ../../Makefile.common-config

CSV_FILES=perf.csv perf-step.csv mem-ideal.csv accuracy.csv

ZELUC += -I ../outlierlib

all: build

bench: bench_per_particles bench_per_steps bench_mem_ideal

include ../../Makefile.common-algo
