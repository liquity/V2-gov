#!/usr/bin/env python3

def main():
    global EPOCH74_GAS0, VOTIUM_GAS0
    if "<FILL ME IN>" in RPC_URL or not RPC_URL:
        sys.exit("ERROR: set RPC_URL at the top of this file, or export RPC_URL=<mainnet archive rpc>.")
    if shutil.which("anvil") is None:
        sys.exit("ERROR: anvil not found on PATH.")
    print(subprocess.run(["anvil", "--version"], capture_output=True, text=True).stdout.strip()
          .splitlines()[:2])
