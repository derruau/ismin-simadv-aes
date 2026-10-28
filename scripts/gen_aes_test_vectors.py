#! /usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Filename: gen_aes_test_vectors.py
Author: DERRUAU Noam
Date: 27-10-2026
Version: 1.0
License: MIT License
Description: 
    This script uses pycryptodome's AES implementation to generate
    lots of plaintext/encryption pairs using a single 128 bytes long key.

    We use AES's ECB mode because each block sent by SystemVerilog 
    is independant from one another and a full reset of the circuit
    is done before each new operation.
"""

from pathlib import Path

from Crypto.Cipher import AES
from Crypto.Random import get_random_bytes

# ================== [CONSTANTES] ================== #

OUTPUT_FILENAME = "data/pt_ct_pairs.csv"

# Nombre de vecteurs de tests aléatoire à générer
N = 100

# Clé de chiffrement utilisée (AES-128)
KEY_HEX = '2b7e151628aed2a6abf7158809cf4f3c'

# ================== [PROGRAMME] ================== #

# Initialisation
# Mode ECB utilisé pour chiffrer chaque bloc indépendament des autres.
key = bytes.fromhex(KEY_HEX)
Cipher = AES.new(key, AES.MODE_ECB)

# Génération de plain texts de 128 bits aléatoire
pt = [get_random_bytes(16) for i in range(N)]

# Génération des paires chiffrées
ct = [Cipher.encrypt(block) for block in pt]

# Création du fichier d'output:
Path(OUTPUT_FILENAME).parent.mkdir(parents=True, exist_ok=True)

# Écriture dans le fichier d'output
with open(OUTPUT_FILENAME, 'w') as f:
    f.write("py_plaintext, py_ciphertext\n")

    lines = [f'{pt[i].hex()}, {ct[i].hex()}\n' for i in range(N)]
    f.writelines(lines)