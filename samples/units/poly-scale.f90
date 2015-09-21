! Run (in the top-directory):
!
!   ./camfort units samples/units/poly-scale.f90 samples/unitso 

program foo 
  implicit none
  
  real, unit(m) :: a = 10
  real, unit(s) :: b = 10
  real :: c, d

  c = square_per_m2(a)
  d = square_per_m2(b)
  
  contains

   real function square_per_m2(x)
     real x
     real, unit(m**2) :: area
     square_per_m2 = (x * x) / area

   end function

end program
