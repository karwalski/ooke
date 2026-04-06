TOKE_STDLIB := $(HOME)/tk/toke/src/stdlib

# Detect platform
UNAME := $(shell uname -s)

CC      := cc
CFLAGS  := -std=c99 -Wall -Wextra -O2 -I$(TOKE_STDLIB) -DTK_HAVE_OPENSSL
LDFLAGS :=
LIBS    := -lssl -lcrypto -lz -lm

ifeq ($(UNAME), Darwin)
    CFLAGS  += -I/opt/homebrew/include
    LDFLAGS += -L/opt/homebrew/lib
endif

OOKE_SRCS := src/main.c \
             src/build.c \
             src/config.c \
             src/template.c \
             src/md.c \
             src/store.c \
             src/ooke_router.c \
             src/serve.c

# toke stdlib sources required by ooke
STDLIB_SRCS := $(TOKE_STDLIB)/str.c \
               $(TOKE_STDLIB)/file.c \
               $(TOKE_STDLIB)/env.c \
               $(TOKE_STDLIB)/log.c \
               $(TOKE_STDLIB)/http.c \
               $(TOKE_STDLIB)/router.c \
               $(TOKE_STDLIB)/ws.c \
               $(TOKE_STDLIB)/encoding.c \
               $(TOKE_STDLIB)/tk_web_glue.c \
               $(TOKE_STDLIB)/tk_runtime.c

# Combine all sources
SRCS := $(OOKE_SRCS) $(STDLIB_SRCS)
OBJS := $(SRCS:.c=.o)

TARGET := ooke

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(TARGET) $(OBJS)

install: $(TARGET)
	install -m 755 $(TARGET) /usr/local/bin/$(TARGET)
