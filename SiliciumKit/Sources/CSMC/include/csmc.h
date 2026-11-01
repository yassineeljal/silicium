#ifndef CSMC_H
#define CSMC_H
#include <stdint.h>
#include <stdbool.h>

/// Ouvre la connexion au pilote AppleSMC. Retourne 0 si échec.
uint32_t csmc_open(void);
void csmc_close(uint32_t conn);
/// Nombre total de clés SMC (-1 si erreur).
int32_t csmc_key_count(uint32_t conn);
/// Nom FourCC de la clé à l'index donné (out = 5 octets, NUL final). Retourne false si échec.
bool csmc_key_at_index(uint32_t conn, uint32_t index, char out[5]);
/// Lit une clé. type = FourCC (5 octets), bytes jusqu'à 32. Retourne la taille lue, ou -1.
int32_t csmc_read_key(uint32_t conn, const char key[4], char type_out[5], uint8_t bytes_out[32]);
#endif
