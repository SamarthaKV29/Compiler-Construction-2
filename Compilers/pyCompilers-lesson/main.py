import os

regs = {
    "AX": [],
    "BX": [],
    "CX": [],
    "DX": []
}
parseTab = []


def preprocess(programfile):
    prog = open(programfile, mode="r")
    statements = prog.read()
    statements = statements.split(";")
    for s in statements:
        if(len(s) <=0):
            statements.remove(s)
    return statements


st = preprocess("test.my")
print st, regs