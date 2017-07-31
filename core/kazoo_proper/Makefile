ROOT = ../..
PROJECT = kazoo_proper

ERLC_OPTS = +'{parse_transform, kz_perf_transform}' +'{lager_extra_sinks, [data]}'

all: compile

include $(ROOT)/make/kz.mk
