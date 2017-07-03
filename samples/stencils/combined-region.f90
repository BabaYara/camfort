! Example of stencils with combined regions
!
! Regions can be combined with intersection (*) or union (+).
program combinedregion
implicit none

integer i
parameter (n=10)
real a(0:n,0:n)
real b(0:n,0:n)

! This is a nine-point stencil
do i=1, n
 do j=1, n
  x = a(i, j) + a(i-1, j) + a(i+1, j)
  y = a(i, j-1) + a(i-1, j-1) + a(i+1, j-1)
  z = a(i, j+1) + a(i-1, j+1) + a(i+1, j+1)
  b(i, j) = (x + y + z) / 9.0
 end do
end do

! This is a five point stencil
do i=1, n
 do j=1, n
  b(i,j) = -4*a(i,j) + a(i-1,j) + a(i,j-1) + a(i,j+1)
 end do
end do

end
