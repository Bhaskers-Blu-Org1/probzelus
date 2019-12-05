all:
	$(MAKE) -C owl
	$(MAKE) -C inference
	
	
examples: all
	$(MAKE) -C examples
	
with-plplot: all
	$(MAKE) -C owl-plplot
	

clean:
	$(MAKE) -C owl clean
	$(MAKE) -C owl-plplot clean
	$(MAKE) -C inference clean
	$(MAKE) -C examples clean

cleanall:
	-rm -f *~
	$(MAKE) -C owl cleanall
	$(MAKE) -C owl-plplot cleanall
	$(MAKE) -C inference cleanall
	$(MAKE) -C examples cleanall

.phony: examples