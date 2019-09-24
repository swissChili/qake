prefix = /usr/local/bin

qake: qake.lua
	cp qake.lua qake

deps:
	luarocks install inspect --local

install: qake
	chmod +x $^
	sudo mv $^ $(prefix)
