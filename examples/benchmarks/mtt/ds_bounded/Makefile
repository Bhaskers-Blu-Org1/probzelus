EX=mtt
ALGO=ds_bounded
NAME=mtt_ds_bounded

include ../../Makefile.common-config

CSV_FILES=perf.csv perf-step.csv mem-ideal.csv accuracy.csv

OWLLIB=../../../../owl
ZELUC +=  -I $(OWLLIB) -I ../mttlib

all: build

bench: bench_per_particles bench_per_steps bench_mem_ideal

include ../../Makefile.common-algo
