      program example8
      implicit none

      integer i, imax
      parameter (imax = 3)
      real a(0:imax)

      do i = 0, imax
c= stencil atMost, readOnce, (forward(depth=2, dim=1)) :: a
            a(i) = a(i) + a(i+2)
      end do

      end
