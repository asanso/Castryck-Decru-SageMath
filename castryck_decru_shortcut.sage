import time
from itertools import product
from helpers import possibly_parallel, supersingular_gens, fast_log3

load('richelot_aux.sage')
load('uvtable.sage')
load('speedup.sage')

# ===================================
# =====  ATTACK  ====================
# ===================================


def CastryckDecruAttack(E_start, P2, Q2, EB, PB, QB, two_i, num_cores=1):
    tim = time.time()

    skB = [] # TERNARY DIGITS IN EXPANSION OF BOB'S SECRET KEY

    # gathering the alpha_i, u, v from table
    expdata = [[0, 0, 0] for _ in range(b-3)]
    for i in range(b%2, b-3, 2):
        index = (b-i) // 2
        row = uvtable[index-1]
        if row[1] <= a:
            expdata[i] = row[1:4]

    # gather digits until beta_1
    bet1 = 0
    while not expdata[bet1][0]:
        bet1 += 1
    bet1 += 1

    ai,u,v = expdata[bet1-1]

    print(f"Determination of first {bet1} ternary digits. We are working with 2^{ai}-torsion.")

    bi = b - bet1
    alp = a - ai

    @possibly_parallel(num_cores)
    def CheckGuess(first_digits):
        print(f"Testing digits: {first_digits}")

        scalar = sum(3^k*d for k,d in enumerate(first_digits))
        tauhatkernel = 3^bi * (P3 + scalar*Q3)

        tauhatkernel_distort = u*tauhatkernel + v*two_i(tauhatkernel)

        C, P_c, Q_c, chainC = AuxiliaryIsogeny(bet1, u, v, E_start, P2, Q2, tauhatkernel, two_i)
        # We have a diagram
        #  C <- Eguess <- E_start
        #  |    |
        #  v    v
        #  CB-> EB
        split = Does22ChainSplit(C, EB, 2^alp*P_c, 2^alp*Q_c, 2^alp*PB, 2^alp*QB, ai)
        #print(split)
        if split:
            print("found")
            Eguess, _ = Pushing3Chain(E_start, tauhatkernel, bet1)

            chain, (E1, E2) = split
            # Compute the 3^b torsion in C
            P3c = chainC(P3)
            Q3c = chainC(Q3)
            # Map it through the (2,2)-isogeny chain
            def apply_chain(c, X):
                #print("chain start", X)
                for f in c:
                    X = f(X)
                    #print("=>", X)
                return X
            P3c_E1, P3c_E2 = apply_chain(chain, (P3c, None))
            Q3c_E1, Q3c_E2 = apply_chain(chain, (Q3c, None))
            print("Computed image of 3-adic torsion in split factors E1xE2")

            Z3 = Zmod(3^b)
            # Determine kernel of the 3^b isogeny.
            # The projection of either E1 or E2 must have 3-adic rank 1.
            # To compute the kernel we choose a symplectic basis of the
            # 3-torsion at the destination, and compute Weil pairings.
            if E2.j_invariant() == Eguess.j_invariant():
                # Correct projection is to E1
                print("Trying to compute kernel to E1")
                E1.set_order((p+1)^2) # keep checks
                P_E1, Q_E1 = supersingular_gens(E1)
                P3_E1 = ((p+1) / 3^b) * P_E1
                Q3_E1 = ((p+1) / 3^b) * Q_E1
                w = P3_E1.weil_pairing(Q3_E1, 3^b)
                # Compute matrix and check for kernel
                M11 = fast_log3(P3c_E1.weil_pairing(P3_E1, 3^b), w)
                M12 = fast_log3(P3c_E1.weil_pairing(Q3_E1, 3^b), w)
                M21 = fast_log3(Q3c_E1.weil_pairing(P3_E1, 3^b), w)
                M22 = fast_log3(Q3c_E1.weil_pairing(Q3_E1, 3^b), w)
                if Z3(M11*M22-M12*M21) == 0:
                    print("Found kernel after split to E1")
                    #print(M)
                    if M21 % 3 != 0:
                        sk = int(-Z3(M11)/Z3(M21))
                        return sk
                    elif M22 % 3 != 0:
                        sk = int(-Z3(M12)/Z3(M22))
                        return sk
            else:
                print("Trying to compute kernel to E2 ")
                E2.set_order((p+1)^2) # keep checks
                P_E2, Q_E2 = supersingular_gens(E2)
                P3_E2 = ((p+1) / 3^b) * P_E2
                Q3_E2 = ((p+1) / 3^b) * Q_E2
                w = P3_E2.weil_pairing(Q3_E2, 3^b)
                # Compute matrix
                M11 = fast_log3(P3c_E2.weil_pairing(P3_E2, 3^b), w)
                M12 = fast_log3(P3c_E2.weil_pairing(Q3_E2, 3^b), w)
                M21 = fast_log3(Q3c_E2.weil_pairing(P3_E2, 3^b), w)
                M22 = fast_log3(Q3c_E2.weil_pairing(Q3_E2, 3^b), w)
                if Z3(M11*M22-M12*M21) == 0:
                    print("Found kernel after split to E2")
                    print(M11)
                    print(M12)
                    print(M21)
                    print(M22)
                    if M21 % 3 != 0:
                        print("if")
                        sk = int(-Z3(M11)/Z3(M21))
                        return sk
                    elif M22 % 3 != 0:
                        print("else")
                        sk = int(-Z3(M12)/Z3(M22))
                        return sk
                     
            return True

    guesses = [ZZ(i).digits(3, padto=bet1) for i in range(3^bet1)]

    for result in CheckGuess(guesses):
        ((first_digits,), _), sk = result
        if sk is not None:
            print("Glue-and-split! These are most likely the secret digits.")
            bobskey = sk
            break

    print(f"In ternary, this is: {Integer(bobskey).digits(base=3)}")
    # Sanity check
    bobscurve, _ = Pushing3Chain(E_start, P3 + bobskey*Q3, b)
    found = bobscurve.j_invariant() == EB.j_invariant()

    if found:
        print(f"Bob's secret key revealed as: {bobskey}")
        print(f"In ternary, this is: {Integer(bobskey).digits(base=3)}")
        print(f"Altogether this took {time.time() - tim} seconds.")
        return bobskey
    else:
        print("Something went wrong.")
        print(f"Altogether this took {time.time() - tim} seconds.")
        return None
