#! /usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Filename: aes_live_test.py
Author: DERRUAU Noam
Date: 27-10-2026
Version: 1.0
License: MIT License
Description: 
    This script uses pycryptodome's AES implementation to encrypt
    or decrypt 128 bytes of data using either a 128 or 256 bytes 
    long key.

    We use AES's ECB mode because each block sent by SystemVerilog 
    is independant from one another and a full reset of the circuit
    is done before each new operation.
"""

from Crypto.Cipher import AES
from enum import Enum

class ENCDEC(Enum):
    DEC = 0
    ENC = 1

def AES_ref_py(data_sv: str , key_sv:str, encdec_sv: ENCDEC) -> str:
    """
    Encrypts or decrypts a block of data using AES-128 or
    AES-256 ECB Mode.

    Arguments:
    - `data_sv`:    The block of data to either encrypt or decrypt.
                    As per the SystemVerilog implementation, it should
                    be 128 bytes long.
                    Format: the string should be formatted like this 
                    for the 0xDEADBEEF value: 'DE AD BE EF'
    - `key_sv`:     The AES key.
                    It should either be 128 or 256 bytes long, as per the
                    SystemVerilog implementation.
                    Format: the string should be formatted like this 
                    for the 0xDEADBEEF value: 'DE AD BE EF'
    - `encdec_sv`:  Whether to perform an encryption or a decryption.
                    Either:
                        - ENCDEC.ENC : For encyphering `data_sv`
                        - ENCDEC.DEC : For decyphering `data_sv`

    Returns: a string containing the hex values of the operation.
    If the string is empty and `data_sv` isn't, an error has occured.

    Example:
    ```python
    # AES-256 encryption Example
    data    = 'A5 0E 36 D5 3B 41 26 61 DA 2A 78 97 B7 D3 C1 C0'
    key     = 'C5 25 91 AB C4 52 CC AA 32 8A D2 FA 64 CF 98 11 FC 46 B3 89 C6 F8 24 E5 5C 27 54 91 6E 11 41 C3'
    
    AES_ref_py(data , key, ENCDEC.ENC)
    >>> '26 D3 05 3B 50 DF 6C C3 23 83 58 91 5C 55 A7 64'
    ```
    """

    # Converting to Bytes
    key_py = bytes.fromhex(key_sv)
    data_py = bytes.fromhex(data_sv)

    # AES initialisation, ECB mode
    Cipher = AES.new(key_py, AES.MODE_ECB)

    # Result of the operation
    op_py: bytes = bytes()

    match encdec_sv:
        case ENCDEC.ENC.value:
            op_py = Cipher.encrypt(data_py)
        case ENCDEC.DEC.value:
            op_py = Cipher.decrypt(data_py)

    return op_py.hex()