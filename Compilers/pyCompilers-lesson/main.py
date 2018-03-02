import os
import re
import regutil

regs = {
    "AX": [],
    "BX": [],
    "CX": [],
    "DX": []
}

functions = {
    1: "int",
    2: "print",
    3: "string"
}


def preprocess(programfile):
    prog = open(programfile, mode="r")
    statements = prog.read()
    # print "Stmnts=", statements
    statements = statements.split(";")
    # print "modedd statements", statements
    cnt = 0
    for s in statements:
        cnt += 1
        # print "stmnt", cnt, " ", s
        if(len(s) <= 0):
            statements.remove(s)
    return statements


st = preprocess("test.my")
variables = {}

def tokenize(stmts):
    for stmt in stmts:
        if(re.match("var (\w)", stmt)):
            val = re.findall("var (\w)", stmt)
            if(len(val) == 1):
                val = val.pop()
                variables[val] = None
        elif(re.match("disp\((\w)\)", stmt)):
            val = re.findall("disp\((\w)\)", stmt)
            if(len(val) == 1):
                val = val.pop()
                if(val in variables):
                    print variables[val]

                

            
            

tokenize(st)
print variables
class ParseTabRow:
    def __init__(self, dT, vN, vVal, fN, fM):
        self.dtype = dT
        self.varName = vN
        self.varVal = vVal
        self.funcName = fN
        self.funcMap = fM

parseTab = []



    


