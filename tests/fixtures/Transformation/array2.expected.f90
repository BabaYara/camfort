program arrays

  integer, parameter :: n = 5
  integer, parameter :: m = 7
  integer, dimension(m,n) :: a
  integer, dimension(n,m) :: b
  integer, dimension(n,m) :: c
  integer, dimension(n,m) :: d
  integer :: i, j
  
  do i = 1, n
     do j = 1, m
        a(j, i) = i*j
        c(i, j) = i*j
     end do
  end do

  b = addAndZeroSwap(n, m, a, b)
  d = addAndZero(n, m, c, d)

  do i = 1, n
     do j = 1, m
        write (*, "(I3) ", advance="no") a(j, i)
     end do
     write (*,*) ""
  end do

  write (*,*) ""
  
  do i = 1, n
     do j = 1, m
        write (*, "(I3) ", advance="no") b(i, j)
     end do
     write (*,*) ""
  end do

  
  write (*,*) ""
  
  do i = 1, n
     do j = 1, m
        write (*, "(I3) ", advance="no") c(i, j)
     end do
     write (*,*) ""
  end do

  
  write (*,*) ""
  
  do i = 1, n
     do j = 1, m
        write (*, "(I3) ", advance="no") d(i, j)
     end do
     write (*,*) ""
  end do
  
  contains

    function addAndZero(n, m, c, d)
      integer :: n, m
      integer, dimension(n, m) :: c
      integer, dimension(n, m) :: d
      integer, dimension(n, m) :: addAndZero
      integer :: i, j
      do i = 1, n
         do j = 1, m
            addAndZero(i, j) = c(i, j) + d(i, j)
            c(i, j) = 0
         end do
      end do
    end function addAndZero

   function addAndZeroSwap(n, m, c, d)
      integer :: n, m
      integer, dimension(m, n) :: c
      integer, dimension(n, m) :: d
      integer, dimension(n, m) :: addAndZero
      integer :: i, j
      do i = 1, n
         do j = 1, m
            addAndZero(i, j) = c(j, i) + d(i, j)
            c(j, i) = 0
         end do
      end do
    end function addAndZero
    
end program arrays
