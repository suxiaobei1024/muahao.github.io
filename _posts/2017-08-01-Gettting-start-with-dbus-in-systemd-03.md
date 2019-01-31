---
layout: post
title: "Getting start with dbus in systemd (03) - sd-bus.h 使用例子 （systemd version>=221）"
author: muahao
tags:
- systemd
---

## sd-bus.h 例子
注意： 

sd-dbus 是systemd提供的lib，但是这个lib，只有在systemd>v221版本后才可以使用，centos 219版本太低，所以不能使用。 

参考： http://0pointer.net/blog/the-new-sd-bus-api-of-systemd.html


```
#cat print-unit-path.c
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>

#include <systemd/sd-bus.h>
#define _cleanup_(f) __attribute__((cleanup(f)))

/* This is equivalent to:
 * busctl call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
 *       org.freedesktop.systemd1.Manager GetUnitByPID $$
 *
 * Compile with 'cc -lsystemd print-unit-path.c'
 */

#define DESTINATION "org.freedesktop.systemd1"
#define PATH        "/org/freedesktop/systemd1"
#define INTERFACE   "org.freedesktop.systemd1.Manager"
#define MEMBER      "GetUnitByPID"

static int log_error(int error, const char *message) {
  fprintf(stderr, "%s: %s\n", message, strerror(-error));
  return error;
}

static int print_unit_path(sd_bus *bus) {
  _cleanup_(sd_bus_message_unrefp) sd_bus_message *m = NULL;
  _cleanup_(sd_bus_error_free) sd_bus_error error = SD_BUS_ERROR_NULL;
  _cleanup_(sd_bus_message_unrefp) sd_bus_message *reply = NULL;
  int r;

  // create m
  r = sd_bus_message_new_method_call(bus, &m,
                                     DESTINATION, PATH, INTERFACE, MEMBER);
  if (r < 0)
    return log_error(r, "Failed to create bus message");

  r = sd_bus_message_append(m, "u", (unsigned) getpid());
  if (r < 0)
    return log_error(r, "Failed to append to bus message");

  r = sd_bus_call(bus, m, -1, &error, &reply);
  if (r < 0)
    return log_error(r, "Call failed");

  const char *ans;
  r = sd_bus_message_read(reply, "o", &ans);
  if (r < 0)
    return log_error(r, "Failed to read reply");

  printf("Unit path is \"%s\".\n", ans);

  return 0;
}

int main(int argc, char **argv) {
  _cleanup_(sd_bus_flush_close_unrefp) sd_bus *bus = NULL;
  int r;

  /* Connect to the system bus */
  r = sd_bus_open_system(&bus);
  if (r < 0)
    return log_error(r, "Failed to acquire bus");

  print_unit_path(bus);
}
```


```
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <systemd/sd-bus.h>

static int method_multiply(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
        int64_t x, y;
        int r;

        /* Read the parameters */
        r = sd_bus_message_read(m, "xx", &x, &y);
        if (r < 0) {
                fprintf(stderr, "Failed to parse parameters: %s\n", strerror(-r));
                return r;
        }

        /* Reply with the response */
        return sd_bus_reply_method_return(m, "x", x * y);
}

static int method_divide(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
        int64_t x, y;
        int r;

        /* Read the parameters */
        r = sd_bus_message_read(m, "xx", &x, &y);
        if (r < 0) {
                fprintf(stderr, "Failed to parse parameters: %s\n", strerror(-r));
                return r;
        }

        /* Return an error on division by zero */
        if (y == 0) {
                sd_bus_error_set_const(ret_error, "net.poettering.DivisionByZero", "Sorry, can't allow division by zero.");
                return -EINVAL;
        }

        return sd_bus_reply_method_return(m, "x", x / y);
}

/* The vtable of our little object, implements the net.poettering.Calculator interface */
static const sd_bus_vtable calculator_vtable[] = {
        SD_BUS_VTABLE_START(0),
        SD_BUS_METHOD("Multiply", "xx", "x", method_multiply, SD_BUS_VTABLE_UNPRIVILEGED),
        SD_BUS_METHOD("Divide",   "xx", "x", method_divide,   SD_BUS_VTABLE_UNPRIVILEGED),
        SD_BUS_VTABLE_END
};

int main(int argc, char *argv[]) {
        sd_bus_slot *slot = NULL;
        sd_bus *bus = NULL;
        int r;

        /* Connect to the user bus this time */
        r = sd_bus_open_user(&bus);
        if (r < 0) {
                fprintf(stderr, "Failed to connect to system bus: %s\n", strerror(-r));
                goto finish;
        }

        /* Install the object */
        r = sd_bus_add_object_vtable(bus,
                                     &slot,
                                     "/net/poettering/Calculator",  /* object path */
                                     "net.poettering.Calculator",   /* interface name */
                                     calculator_vtable,
                                     NULL);
        if (r < 0) {
                fprintf(stderr, "Failed to issue method call: %s\n", strerror(-r));
                goto finish;
        }

        /* Take a well-known service name so that clients can find us */
        r = sd_bus_request_name(bus, "net.poettering.Calculator", 0);
        if (r < 0) {
                fprintf(stderr, "Failed to acquire service name: %s\n", strerror(-r));
                goto finish;
        }

        for (;;) {
                /* Process requests */
                r = sd_bus_process(bus, NULL);
                if (r < 0) {
                        fprintf(stderr, "Failed to process bus: %s\n", strerror(-r));
                        goto finish;
                }
                if (r > 0) /* we processed a request, try to process another one, right-away */
                        continue;

                /* Wait for the next request to process */
                r = sd_bus_wait(bus, (uint64_t) -1);
                if (r < 0) {
                        fprintf(stderr, "Failed to wait on bus: %s\n", strerror(-r));
                        goto finish;
                }
        }

finish:
        sd_bus_slot_unref(slot);
        sd_bus_unref(bus);

        return r < 0 ? EXIT_FAILURE : EXIT_SUCCESS;
}

```


### Refs
http://0pointer.net/blog/the-new-sd-bus-api-of-systemd.html
