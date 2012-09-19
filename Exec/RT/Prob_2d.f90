
      subroutine PROBINIT (init,name,namlen,problo,probhi)

      use probdata_module
      use eos_module, only : gamma_const
      implicit none

      integer init, namlen
      integer name(namlen)
      double precision problo(2), probhi(2)

      integer untin,i

      namelist /fortin/ denerr,dengrad,max_denerr_lev,max_dengrad_lev, &
           presserr,pressgrad,max_presserr_lev,max_pressgrad_lev,frac

!
!     Build "probin" filename -- the name of file containing fortin namelist.
!     
      integer maxlen
      parameter (maxlen=256)
      character probin*(maxlen)

      if (namlen .gt. maxlen) then
         write(6,*) 'probin file name too long'
         stop
      end if

      do i = 1, namlen
         probin(i:i) = char(name(i))
      end do
         
! set namelist defaults here
      frac = 0.5

!     Read namelists
      untin = 9
      open(untin,file=probin(1:namlen),form='formatted',status='old')
      read(untin,fortin)
      close(unit=untin)

!     set local variable defaults
      center(1) = frac*(problo(1)+probhi(1))
      center(2) = frac*(problo(2)+probhi(2))

      end

! ::: -----------------------------------------------------------
! ::: This routine is called at problem setup time and is used
! ::: to initialize data on each grid.  
! ::: 
! ::: NOTE:  all arrays have one cell of ghost zones surrounding
! :::        the grid interior.  Values in these cells need not
! :::        be set here.
! ::: 
! ::: INPUTS/OUTPUTS:
! ::: 
! ::: level     => amr level of grid
! ::: time      => time at which to init data             
! ::: lo,hi     => index limits of grid interior (cell centered)
! ::: nstate    => number of state components.  You should know
! :::		   this already!
! ::: state     <=  Scalar array
! ::: delta     => cell size
! ::: xlo,xhi   => physical locations of lower left and upper
! :::              right hand corner of grid.  (does not include
! :::		   ghost region).
! ::: -----------------------------------------------------------
      subroutine ca_initdata(level,time,lo,hi,nscal, &
                             state,state_l1,state_l2,state_h1,state_h2, &
                             delta,xlo,xhi)
        use probdata_module
        use meth_params_module, only : NVAR, URHO, UMX, UMY, UEDEN, UEINT, UFS, UTEMP
        
        implicit none
        
        integer level, nscal
        integer lo(2), hi(2)
        integer state_l1,state_l2,state_h1,state_h2
        double precision xlo(2), xhi(2), time, delta(2)
        double precision state(state_l1:state_h1,state_l2:state_h2,NVAR)
        
        integer i,j
        double precision x,y,pres,presbase,presmid,pertheight
        
        double precision pi
        parameter (pi=3.1415926535897932384)
        
        double precision rho1,rho2

        rho1 = 1.0
        rho2 = 2.0

        presbase = 5.0
        presmid  = 5.0 - rho1*center(2)
        
        state(:,:,UMX)   = 0.0
        state(:,:,UMY)   = 0.0
        state(:,:,UTEMP) = 0.0

        do j = lo(2), hi(2)
           y = (j+0.5)*delta(2)
           do i = lo(1), hi(1)
              
              if (y .lt. center(2)) then
                 pres = presbase - rho1*y
                 state(i,j,UEDEN) = pres / 0.4
                 state(i,j,UEINT) = pres / 0.4
              else
                 pres = presmid - rho2*(y-center(2))
                 state(i,j,UEDEN) = pres / 0.4
                 state(i,j,UEINT) = pres / 0.4
              end if
              
           enddo
        enddo
        
        do j = lo(2), hi(2)
           y = (j+0.5)*delta(2)
           do i = lo(1), hi(1)
              x = (i+0.5)*delta(1)

              pertheight = 0.005*(cos(4.0*pi*x)+cos(4.d0*pi*(0.5-x))) + 0.5
              state(i,j,URHO) = rho1 + ((rho2-rho1)/2.0)*(1+tanh((y-pertheight)/0.005))
              state(i,j,UFS) = state(i,j,URHO)
              
           enddo
        enddo

      end subroutine ca_initdata

! ::: -----------------------------------------------------------

     subroutine ca_hypfill(adv,adv_l1,adv_l2,adv_h1,adv_h2, &
                           domlo,domhi,delta,xlo,time,bc)
 
     use meth_params_module, only : NVAR, URHO, UMX, UMY, UEDEN, UEINT, UFS, UTEMP

     implicit none
     include 'bc_types.fi'
     integer adv_l1,adv_l2,adv_h1,adv_h2
     integer bc(2,2,*)
     integer domlo(2), domhi(2)
     double precision delta(2), xlo(2), time
     double precision adv(adv_l1:adv_h1,adv_l2:adv_h2,NVAR)

     integer i,j,n
     double precision y,pres,presbase

     presbase = 5.0

      do n = 1,NVAR
         call filcc(adv(adv_l1,adv_l2,n),adv_l1,adv_l2,adv_h1,adv_h2, &
              domlo,domhi,delta,xlo,bc(1,1,n))
      enddo
      
      do n=1,NVAR
         !        XLO
         if ( bc(1,1,n).eq.EXT_DIR .and. adv_l1.lt.domlo(1)) then
            print *,'SHOULD NEVER GET HERE bc(1,1,n) .eq. EXT_DIR) '
            stop
         end if
         
         !        XHI
         if ( bc(1,2,n).eq.EXT_DIR .and. adv_h1.gt.domhi(1)) then
            print *,'SHOULD NEVER GET HERE bc(1,2,n) .eq. EXT_DIR) '
            stop
         end if
         
         !        YLO
         if ( bc(2,1,n).eq.EXT_DIR .and. adv_l2.lt.domlo(2)) then
            do j=adv_l2,domlo(2)-1
               y = (j+0.5d0)*delta(2)
               do i=adv_l1,adv_h1
                  if (n .eq. URHO)  adv(i,j,n) = 1.0
                  if (n .eq. UMX)   adv(i,j,n) = 0.0
                  if (n .eq. UMY)   adv(i,j,n) = 0.0
                  if (n .eq. UEDEN .or. n .eq. UEINT) then
                     pres = presbase - y
                     adv(i,j,n) = pres / 0.4
                  end if
                  
                  if (n .eq. UFS)   adv(i,j,n) = 1.0
                  if (n .eq. UTEMP) adv(i,j,n) = 0.0
               end do
            end do
         end if
         
         !        YHI
         if ( bc(2,2,n).eq.EXT_DIR .and. adv_h2.gt.domhi(2)) then
            print *,'SHOULD NEVER GET HERE bc(2,2,n) .eq. EXT_DIR) '
            stop
         end if

      end do

      end subroutine ca_hypfill

! ::: -----------------------------------------------------------

      subroutine ca_denfill(adv,adv_l1,adv_l2,adv_h1,adv_h2, &
           domlo,domhi,delta,xlo,time,bc)

      implicit none
      include 'bc_types.fi'
      integer adv_l1,adv_l2,adv_h1,adv_h2
      integer bc(2,2,*)
      integer domlo(2), domhi(2)
      double precision delta(2), xlo(2), time
      double precision adv(adv_l1:adv_h1,adv_l2:adv_h2)

!     Note: this function should not be needed, technically, but is provided
!     to filpatch because there are many times in the algorithm when just
!     the density is needed.  We try to rig up the filling so that the same
!     function is called here and in hypfill where all the states are filled.

      call filcc(adv,adv_l1,adv_l2,adv_h1,adv_h2,domlo,domhi,delta,xlo,bc)

!     XLO
      if ( bc(1,1,1).eq.EXT_DIR .and. adv_l1.lt.domlo(1)) then
         print *,'SHOULD NEVER GET HERE bc(1,1,1) .eq. EXT_DIR) '
         stop
      end if

!     XHI
      if ( bc(1,2,1).eq.EXT_DIR .and. adv_h1.lt.domhi(1)) then
         print *,'SHOULD NEVER GET HERE bc(1,2,1) .eq. EXT_DIR) '
         stop
      end if

!     YLO
      if ( bc(2,1,1).eq.EXT_DIR .and. adv_l2.lt.domlo(2)) then
         print *,'SHOULD NEVER GET HERE bc(2,1,1) .eq. EXT_DIR) '
         stop
      end if

!     YHI
      if ( bc(2,2,1).eq.EXT_DIR .and. adv_h2.gt.domhi(2)) then
         print *,'SHOULD NEVER GET HERE bc(2,2,1) .eq. EXT_DIR) '
         stop
      end if

      end subroutine ca_denfill

      subroutine ca_gravxfill(grav,grav_l1,grav_l2,grav_h1,grav_h2, &
           domlo,domhi,delta,xlo,time,bc)

      use probdata_module
      implicit none
      include 'bc_types.fi'

      integer :: grav_l1,grav_l2,grav_h1,grav_h2
      integer :: bc(2,2,*)
      integer :: domlo(2), domhi(2)
      double precision delta(2), xlo(2), time
      double precision grav(grav_l1:grav_h1,grav_l2:grav_h2)

      call filcc(grav,grav_l1,grav_l2,grav_h1,grav_h2,domlo,domhi,delta,xlo,bc)

      end subroutine ca_gravxfill

! ::: -----------------------------------------------------------

      subroutine ca_gravyfill(grav,grav_l1,grav_l2,grav_h1,grav_h2, &
           domlo,domhi,delta,xlo,time,bc)

      use probdata_module
      implicit none
      include 'bc_types.fi'

      integer :: grav_l1,grav_l2,grav_h1,grav_h2
      integer :: bc(2,2,*)
      integer :: domlo(2), domhi(2)
      double precision delta(2), xlo(2), time
      double precision grav(grav_l1:grav_h1,grav_l2:grav_h2)

      call filcc(grav,grav_l1,grav_l2,grav_h1,grav_h2,domlo,domhi,delta,xlo,bc)

      end subroutine ca_gravyfill
