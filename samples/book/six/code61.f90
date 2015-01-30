!!!!!!!!!!!!!!!!!!!!!!!!!!!   Program 6.1   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!                                                                       !
! Please Note:                                                          !
!                                                                       !
! (1) This computer program is written by Tao Pang in conjunction with  !
!     his book, "An Introduction to Computational Physics," published   !
!     by Cambridge University Press in 1997.                            !
!                                                                       !
! (2) No warranties, express or implied, are made for this program.     !
!                                                                       !
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
PROGRAM BENCH
!
! This program solves the problem of a person sitting on a
! bench as described in the text.  Copyright (c) Tao Pang 1997.
!
  IMPLICIT NONE
  INTEGER, PARAMETER :: N=99
  INTEGER :: I
  REAL :: XL,H,H2,Y0,X0,RHO,G,F0,D,E,Ee0,XD
  REAL, DIMENSION (N):: B,X,Y,W,U
!
  XL  = 3.0
  H   = XL/(N+1)
  H2  = H*H
  Y0  = 1.0E09*0.03**3*0.20/3.0
  X0  = 0.25
  RHO = 3.0
  G   = 9.8
  F0  = 200.0
  D   = 2.0
  E   =-1.0
  Ee0  = 1.0/EXP(1.0)
!
! Find elements in L and U
!
  W(1) =  D
  U(1) =  E/D
  DO I = 2, N
    W(I) = D-E*U(I-1)
    U(I) = E/W(I)
  END DO
!
! Assign the array B
!
  DO I = 1, N
    XD   =  H*I
    B(I) = -H2*RHO*G
    IF (ABS(XD-XL/2.0).LT.X0) THEN
      B(I) = B(I)-H2*F0*(EXP(-((XD-XL/2)/X0)**2)-Ee0)
    END IF
    B(I) = B(I)/Y0
  END DO
!
! Find the solution of the curvature
!
  Y(1) = B(1)/W(1)
  DO I = 2, N
    Y(I) = (B(I)+Y(I-1))/W(I)
  END DO
!
  X(N) = Y(N)
  DO I = N-1,1,-1
        X(I) = Y(I)-U(I)*X(I+1)
  END DO
  WRITE(6,"(2F20.10)") (H*I,100*X(I),I=1,N)
END PROGRAM BENCH
