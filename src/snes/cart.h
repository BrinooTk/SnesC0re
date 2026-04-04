
#ifndef CART_H
#define CART_H

#include <stdint.h>
#include <stdbool.h>

typedef struct Cart Cart;

#include "snes.h"
#include "statehandler.h"

struct Cart {
  Snes* snes;
  uint8_t type;
  bool ownsRom;

  uint8_t* rom;
  uint32_t romSize;
  uint8_t* ram;
  uint32_t ramSize;
  bool batteryDirty;
  uint8_t ramStorage[0x20000];
};

// TODO: how to handle reset & load?

Cart* cart_init(Snes* snes);
void cart_free(Cart* cart);
void cart_reset(Cart* cart); // will reset special chips etc, general reading is set up in load
bool cart_handleTypeState(Cart* cart, StateHandler* sh);
void cart_handleState(Cart* cart, StateHandler* sh);
void cart_load(Cart* cart, int type, uint8_t* rom, int romSize, int ramSize); // loads rom, sets up ram buffer
void cart_load_owned(Cart* cart, int type, uint8_t* rom, int romSize, int ramSize); // takes ownership of rom buffer
bool cart_handleBattery(Cart* cart, bool save, uint8_t* data, int* size); // saves/loads ram
uint8_t cart_read(Cart* cart, uint8_t bank, uint16_t adr);
void cart_write(Cart* cart, uint8_t bank, uint16_t adr, uint8_t val);

#endif
