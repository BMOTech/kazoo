ROOT = ../..
PROJECT = sup

all: ebin/sup.app sup

ebin/sup.app:
	@$(REBAR) compile

sup:
	@$(REBAR) escriptize

clean:
	rm ./sup

include $(ROOT)/make/kz.mk
