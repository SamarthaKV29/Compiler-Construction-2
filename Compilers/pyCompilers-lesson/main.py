import os
import re
import regutil

def printProg(stmts):
    print "######################################################################################"
    for row in stmts:
        print row
    print "######################################################################################"

class ParseTabRow:
    def __init__(self, dT, vN, vVal, fN, fM):
        self.dtype = dT
        self.varName = vN
        self.varVal = vVal
        self.funcName = fN
        self.funcMap = fM
    def toList(self):
        return list([
            self.dtype,
            self.varName,
            self.varVal,
            self.funcName,
            self.funcMap,
        ])

parseTab = []

regs = {
    "AX": [],
    "BX": [],
    "CX": [],
    "DX": []
}

functions = {
    1: "var",
    2: "disp",
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


def tokenize(stmts):
    for stmt in stmts:
        if(re.match("var (.+)", stmt)):
            val = re.findall("var (.+)", stmt)
            if(len(val) == 1):
                val = val.pop()
                if(type(val) != type(0)):
                    val = str(val)

                    if(val.find("=") == -1):
                        val = str(val)
                        parserow = ParseTabRow("var", val, None, None, None)
                        parseTab.append(parserow.toList())
                    elif(val.find("=") != -1):
                        val = str(val).strip(" ")
                        val = val.split("=")
                        parserow = ParseTabRow("var", str(val[0]), int(val[1]), None, None)
                        parseTab.append(parserow.toList())
                    
                else:
                    print "type error in statement ", list(stmts).index(stmt)

        elif re.match("disp\((.+)\)", stmt):
            val = re.findall("disp\((.+)\)", stmt)
            if(len(val) == 1):
                val = val.pop()
            try:
                val = int(val)
            except:
                val = str(val)
            parserow = None
            if(type(val) == type(0)):
                parserow = ParseTabRow("int", None, val, "disp", "disp")
                
            else:
                if(str(val).startswith("\"") and str(val).endswith("\"")):
                    parserow = ParseTabRow("string", None, val, "disp", "disp")
                else:
                    parserow = ParseTabRow("var", val, None, "disp", "disp")
            parseTab.append(parserow.toList())
        else:
            print "Invalid syntax in statement", list(stmts).index(stmt)+1
                
def evaluate(pT):
    print parseTab
    return
#Print the program for verification
printProg(st) 
#Generate the tokens
tokenize(st)
evaluate(parseTab)



    


