      program one
      implicit none

      integer i, j, imax, jmax
      parameter (imax = 3, jmax = 3)

      real a(0:imax,0:jmax), b(0:imax,0:jmax), c

      call foo(b)

! some kind of setup
      do 1 i = 0, imax
         do 2 j = 0, jmax
            a(i,j) = i+j
 2       continue
 1    continue

      do i = 0, imax
        a(i,0:jmax) = a(i,0) * b(1:imax,1:jmax)*p(1:imax,1:jmax)
      end do
            
! compute mean
      do 3 i = 1, (imax-1)
         
         a(1:imax,1:jmax) = b(i, j)
         do 4 j = 1, (jmax-1)
            if (.true.) then
            a(i,j) = (a(i-1,j) + a(i,j) + a(i+1,j)  &
                 &              + a(i,j-1) + a(i,j+1)) / 5.0
            b(1:imax,1:jmax) = a(1:imax, 1:jmax)*p(1:imax, 1:jmax) + b(1:imax,1:jmax)*p(1:imax,1:jmax)
            end if
 4       continue
 3    continue

      a(1:imax,1:jmax) = b(1:imax,1:jmax)*p(1:imax,1:jmax) + a(1:imax,1:jmax)

      end
