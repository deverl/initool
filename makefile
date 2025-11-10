
PLATFORM := $(shell uname)

INSTALL_TARGET=~/bin


CPP_FLAGS = -c -Wall -pedantic --std=c++20 -DPLATFORM=$(PLATFORM)

ifeq ($(PLATFORM),Darwin)
    BREW_HOME_DIR=`brew --prefix`
    CPP := $(shell /bin/ls -1 $(BREW_HOME_DIR)/bin/g++* | sed 's/@//g' | sed 's/^.*g++/g++/g')
    PATH := $(BREW_HOME_DIR)/bin:${PATH}
    # Optionally, just set CPP := clang++
else
    CPP := g++
endif

ifeq ($(PLATFORM),Linux)
    CPP_FLAGS += -DLINUX -D_LINUX -D__LINUX__
endif


ifdef DEBUG
    CPP_FLAGS += -g3 -O0 -DDEBUG -D_DEBUG
    OBJDIR := $(PLATFORM)_objd
else
    CPP_FLAGS += -O3 -DNDEBUG -DRELEASE
    OBJDIR := $(PLATFORM)_objn
endif


.DEFAULT : all

all : $(OBJDIR)/initool

.PHONY : clean test install


dep : $(DEP_FILES)

-include $(OBJ_FILES:.o=.d)

CPP_SRC_FILES := initool.cpp

OBJ_LIST := $(CPP_SRC_FILES:.cpp=.o) $(C_SRC_FILES:.c=.o)
OBJ_FILES := $(addprefix $(OBJDIR)/, $(OBJ_LIST))
DEP_FILES := $(OBJ_FILES:.o=.d)


$(OBJDIR)/initool : $(OBJ_FILES) makefile
	@if [ ! -d $(@D) ] ; then mkdir -p $(@D) ; fi
	@echo "Linking $@"
	$(CPP) -o $@ $(OBJ_FILES)

$(OBJDIR)/%.o : %.cpp makefile $(OBJDIR)/%.d
	@if [ ! -d $(@D) ] ; then mkdir -p $(@D) ; fi
	@echo "Compiling $<"
	$(CPP) $(CPP_FLAGS) -o $@ $<

$(OBJDIR)/%.d : %.cpp makefile
	@if [ ! -d $(@D) ] ; then mkdir -p $(@D) ; fi
	@echo "Generating dependencies for $<"
	@$(CPP) $(CPP_FLAGS) -MM -MT $@ $< > $(@:.o=.d)


clean:
	rm -rf initool *.o initool.dSYM $(OBJDIR)


test: $(OBJDIR)/initool
	$(OBJDIR)/initool --get sample.ini  CLIENT   phone
	$(OBJDIR)/initool --get sample.ini  client   PHONE
	$(OBJDIR)/initool --get sample.ini  user     email
	$(OBJDIR)/initool --get sample.ini  USER     USERNAME


# Currently only works on the mac platform.
install: $(OBJDIR)/initool
	cp $(OBJDIR)/initool $(INSTALL_TARGET)/



