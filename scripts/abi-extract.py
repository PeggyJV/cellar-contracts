"""Pulls the "abi" field out from the hardhat-compiled Solidity contract, 
AaveStablecoinCellar. 

Used by the subgraph team.
"""

__author__ = "Unique Divine"

import os
import json
from typing import Dict, Union, List

def init():
    """Moves the current directory to the repo level and verifies all of the 
    expected directories are visible.

    Note: You need to run this script from the repo level,
    not from inside the scripts directory.
    """

    if os.path.dirname(__file__) == "scripts":
        os.chdir("..")
    else:
        expected_directories = ["scripts", "contracts", "artifacts"]
        assert [ed in os.listdir() for ed in expected_directories]

def abi_fname_and_path():
    contract_name: str = "AaveV2StablecoinCellar"
    contract_fname = contract_name + ".sol"
    abi_fname = contract_name + ".json"

    breakpoint()
    abi_path = os.path.join("artifacts", "contracts", contract_fname, abi_fname)
    assert os.path.exists(abi_path)
    return abi_fname, abi_path

init()
abi_fname, abi_path = abi_fname_and_path()

with open(abi_path, 'r') as fh:
    compiled_abi_file: dict = json.load(fh)
    assert isinstance(compiled_abi_file, dict)
    abi = compiled_abi_file['abi']
    assert isinstance(abi, list)

save_dir_name = "out"
if not os.path.exists(save_dir_name):
    os.mkdir(save_dir_name)
abi_save_path = os.path.join(save_dir_name, abi_fname)
with open(abi_save_path, 'w') as fh:
    json.dump(abi, fh, indent=2)
    print(f"ABI saved successfully: {abi_save_path}")

