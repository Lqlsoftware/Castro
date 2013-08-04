module riemann_module

  implicit none

  private

  public riemannus, riemanncg

contains

  subroutine riemanncg(ql,qr,qpd_l1,qpd_l2,qpd_l3,qpd_h1,qpd_h2,qpd_h3, &
                       gamcl,gamcr,cav,smallc,gd_l1,gd_l2,gd_h1,gd_h2, &
                       uflx,uflx_l1,uflx_l2,uflx_l3,uflx_h1,uflx_h2,uflx_h3, &
                       ugdnv,pgdnv,pg_l1,pg_l2,pg_l3,pg_h1,pg_h2,pg_h3, &
                       idir,ilo,ihi,jlo,jhi,kc,kflux)

    ! this implements the approximate Riemann solver of Colella & Glaz (1985)

    use bl_error_module
    use network, only : nspec, naux
    use prob_params_module, only : physbc_lo,Symmetry
    use meth_params_module, only : QVAR, NVAR, QRHO, QU, QV, QW, &
                                   QPRES, QREINT, QESGS, QFA, QFS, &
                                   QFX, URHO, UMX, UMY, UMZ, UEDEN, UEINT, &
                                   UESGS, UFA, UFS, UFX, &
                                   nadv, small_dens, small_pres

    double precision, parameter:: small = 1.d-8
    double precision, parameter:: twothirds = 2.d0/3.d0

    integer :: qpd_l1,qpd_l2,qpd_l3,qpd_h1,qpd_h2,qpd_h3
    integer :: gd_l1,gd_l2,gd_h1,gd_h2
    integer :: uflx_l1,uflx_l2,uflx_l3,uflx_h1,uflx_h2,uflx_h3
    integer :: pg_l1,pg_l2,pg_l3,pg_h1,pg_h2,pg_h3
    integer :: idir,ilo,ihi,jlo,jhi
    integer :: i,j,kc,kflux

    double precision :: ql(qpd_l1:qpd_h1,qpd_l2:qpd_h2,qpd_l3:qpd_h3,QVAR)
    double precision :: qr(qpd_l1:qpd_h1,qpd_l2:qpd_h2,qpd_l3:qpd_h3,QVAR)
    double precision ::  gamcl(gd_l1:gd_h1,gd_l2:gd_h2)
    double precision ::  gamcr(gd_l1:gd_h1,gd_l2:gd_h2)
    double precision ::    cav(gd_l1:gd_h1,gd_l2:gd_h2)
    double precision :: smallc(gd_l1:gd_h1,gd_l2:gd_h2)
    double precision :: uflx(uflx_l1:uflx_h1,uflx_l2:uflx_h2,uflx_l3:uflx_h3,NVAR)
    double precision :: ugdnv(pg_l1:pg_h1,pg_l2:pg_h2,pg_l3:pg_h3)
    double precision :: pgdnv(pg_l1:pg_h1,pg_l2:pg_h2,pg_l3:pg_h3)

    integer :: n, nq
    integer :: iadv, ispec, iaux
    
    double precision :: rgdnv,v1gdnv,v2gdnv,regdnv,ustar,gamgdnv
    double precision :: rl, ul, v1l, v2l, pl, rel
    double precision :: rr, ur, v1r, v2r, pr, rer
    double precision :: wl, wr, rhoetot, scr
    double precision :: rstar, cstar, estar, pstar
    double precision :: ro, uo, po, reo, co, gamco, entho
    double precision :: sgnm, spin, spout, ushock, frac
    double precision :: wsmall, csmall,qavg
    double precision :: rho_K_contrib

    double precision :: clsq, clsql, clsqr, wlsq, wosq, wrsq, wo
    double precision :: zm, zp
    double precision :: denom, dpditer, dpjmp
    double precision :: gamc_bar, game_bar
    double precision :: gamel, gamer, gameo, gamstar, gmin, gmax, gdot

    integer :: iter
    integer, parameter :: iter_max= 8
    double precision, parameter :: tol = 1.d-5
    double precision :: err

    logical :: converged

    double precision :: pstnm1
    double precision :: taul, taur, tauo
    double precision :: ustarm, ustarp, ustnm1, ustnp1

    double precision, parameter :: weakwv = 1.d-3

    !$OMP PARALLEL DO PRIVATE(i,j) &
    !$OMP PRIVATE(rl,ul,v1l,v2l,pl,rel,rr,ur,v1r,v2r,pr,rer) &
    !$OMP PRIVATE(taul,taur,clsql,clsqr,gamel,gamer,gmin,gmax) &
    !$OMP PRIVATE(game_bar,gamc_bar,gdot,csmall,wsmall,wl,wr) &
    !$OMP PRIVATE(pstar,gamstar,wlsq,wrsq,pstnm1) &
    !$OMP PRIVATE(ustarp,ustarm,converged,iter,ustnm1,ustnp1) &
    !$OMP PRIVATE(dpditer,zp,zm,denom,err,ustar) &
    !$OMP PRIVATE(ro,uo,po,tauo,reo,gamco,gameo,co,clsq,wosq,sgnm,wo,dpjmp) &
    !$OMP PRIVATE(rstar,entho,estar,cstar,spout,spin,ushock,scr,frac) &
    !$OMP PRIVATE(v1gdnv,v2gdnv,rgdnv,gamgdnv) &
    !$OMP PRIVATE(rhoetot,n,nq,qavg,rho_K_contrib,iadv,ispec,iaux)
    do j = jlo, jhi
       do i = ilo, ihi

          ! left state
          rl = max(ql(i,j,kc,QRHO),small_dens)
          
          ! pick left velocities based on direction
          if(idir.eq.1) then
             ul  = ql(i,j,kc,QU)
             v1l = ql(i,j,kc,QV)
             v2l = ql(i,j,kc,QW)
          elseif(idir.eq.2) then
             ul  = ql(i,j,kc,QV)
             v1l = ql(i,j,kc,QU)
             v2l = ql(i,j,kc,QW)
          else
             ul  = ql(i,j,kc,QW)
             v1l = ql(i,j,kc,QU)
             v2l = ql(i,j,kc,QV)
          endif
          
          pl  = max(ql(i,j,kc,QPRES ),small_pres)
          rel =     ql(i,j,kc,QREINT)


          ! right state
          rr = max(qr(i,j,kc,QRHO),small_dens)
          
          ! pick right velocities based on direction
          if(idir.eq.1) then
             ur  = qr(i,j,kc,QU)
             v1r = qr(i,j,kc,QV)
             v2r = qr(i,j,kc,QW)
          elseif(idir.eq.2) then
             ur  = qr(i,j,kc,QV)
             v1r = qr(i,j,kc,QU)
             v2r = qr(i,j,kc,QW)
          else
             ur  = qr(i,j,kc,QW)
             v1r = qr(i,j,kc,QU)
             v2r = qr(i,j,kc,QV)
          endif
          
          pr  = max(qr(i,j,kc,QPRES),small_pres)
          rer =     qr(i,j,kc,QREINT)

            
          ! common quantities
          taul = 1.d0/rl
          taur = 1.d0/rr
          
          ! lagrangian sound speeds
          clsql = gamcl(i,j)*pl*rl
          clsqr = gamcr(i,j)*pr*rr
          
          ! gamma_e = p/(rho e) + 1

          ! Note: in the original Colella & Glaz paper, they predicted
          ! gamma_e to the interfaces using a special (non-hyperbolic)
          ! evolution equation.  In Castro, we instead bring (rho e)
          ! to the edges, so we construct the necessary gamma_e here from
          ! what we have on the interfaces.
          gamel = pl/rel + 1
          gamer = pr/rer + 1
          
          ! these should consider a wider average of the cell-centered
          ! gammas
          gmin = min(gamel, gamer, 4.d0/3.d0)
          gmax = max(gamel, gamer, 5.d0/3.d0)
          
          game_bar = 0.5d0*(gamel + gamer)
          gamc_bar = 0.5d0*(gamcl(i,j) + gamcr(i,j))
          
          gdot = 2.d0*(1.d0 - game_bar/gamc_bar)*(game_bar - 1.0)
          
          csmall = smallc(i,j)
          wsmall = small_dens*csmall
          wl = max(wsmall,sqrt(abs(clsql)))
          wr = max(wsmall,sqrt(abs(clsqr)))
          
          ! make an initial guess for pstar -- this is a two-shock 
          ! approximation
          pstar = ((wr*pl + wl*pr) + wl*wr*(ul - ur))/(wl + wr)
          pstar = max(pstar,small_pres)

          ! get the shock speeds -- this computes W_s from CG Eq. 34
          call wsqge(pl,taul,gamel,gdot,  &
                     gamstar,pstar,wlsq,clsql,gmin,gmax)

          call wsqge(pr,taur,gamer,gdot,  &
                     gamstar,pstar,wrsq,clsqr,gmin,gmax)

          pstnm1 = pstar

          wl = sqrt(wlsq)
          wr = sqrt(wrsq)

          ! R-H jump conditions give ustar across each wave -- these should
          ! be equal when we are done iterating
          ustarp = ul - (pstar-pl)/wl
          ustarm = ur + (pstar-pr)/wr

          ! revise our pstar guess
          pstar = ((wr*pl + wl*pr) + wl*wr*(ul - ur))/(wl + wr)
          pstar = max(pstar,small_pres)

          ! sectant iteration
          converged = .false.
          iter = 1
          do while (iter < iter_max .and. .not. converged)
               
             call wsqge(pl,taul,gamel,gdot,  &
                        gamstar,pstar,wlsq,clsql,gmin,gmax)

             call wsqge(pr,taur,gamer,gdot,  &
                        gamstar,pstar,wrsq,clsqr,gmin,gmax)

             wl = 1.d0 / sqrt(wlsq)
             wr = 1.d0 / sqrt(wrsq)
             
             ustnm1 = ustarm
             ustnp1 = ustarp
             
             ustarm = ur-(pr-pstar)*wr
             ustarp = ul+(pl-pstar)*wl
             
             dpditer=abs(pstnm1-pstar)
             
             zp=abs(ustarp-ustnp1)
             if(zp-weakwv*cav(i,j) <= 0.d0)then
                zp = dpditer*wl
             endif
             
             zm=abs(ustarm-ustnm1)
             if(zm-weakwv*cav(i,j) <= 0.d0)then
                zm = dpditer*wr
             endif
             
             ! the new pstar is found via CG Eq. 18
             denom=dpditer/max(zp+zm,small*(cav(i,j)))
             pstnm1 = pstar
             pstar=pstar-denom*(ustarm-ustarp)
             pstar=max(pstar,small_pres)

             err = abs(pstar - pstnm1)
             if (err < tol*pstar) converged = .true.

             iter = iter + 1
             
          enddo

          if (.not. converged) then
             call bl_error("ERROR: non-convergence in the Riemann solver")
          endif
          
          
          ! we converged!  construct the single ustar for the region
          ! between the left and right waves
          ustar = 0.5d0* ( ustarp + ustarm )

          
          ! sample the solution -- here we look first at the direction
          ! that the contact is moving.  This tells us if we need to
          ! worry about the L/L* states or the R*/R states.  
          if (ustar .gt. 0.d0) then
             ro = rl
             uo = ul
             po = pl
             tauo = taul
             reo = rel
             gamco = gamcl(i,j)
             gameo = gamel
             
          else if (ustar .lt. 0.d0) then
             ro = rr
             uo = ur
             po = pr
             tauo = taur
             reo = rer
             gamco = gamcr(i,j)
             gameo = gamer
          else
             ro = 0.5d0*(rl+rr)
             uo = 0.5d0*(ul+ur)
             po = 0.5d0*(pl+pr)
             tauo = 1.d0/ro
             reo = 0.5d0*(rel+rer)
             gamco = 0.5d0*(gamcl(i,j)+gamcr(i,j))
             gameo = 0.5d0*(gamel + gamer)
          endif

          ro = max(small_dens,ro)
         
          co = sqrt(abs(gamco*po/ro))
          co = max(csmall,co)
          clsq = (co*ro)**2

          ! now that we know which state (left or right) we need to worry 
          ! about, get the value of gamstar and wosq across the wave we
          ! are dealing with.
          call wsqge(po,tauo,gameo,gdot,   &
                     gamstar,pstar,wosq,clsq,gmin,gmax)

          sgnm = sign(1.d0,ustar)
          
          wo = sqrt(wosq)
          dpjmp = pstar - po

          ! is this max really necessary?
          rstar=max(1.d0-ro*dpjmp/wosq, (gameo-1.)/(gameo+1.))
          rstar=ro/rstar
          rstar = max(small_dens,rstar)

          entho = (reo/ro + po/ro)/co**2
          estar = reo + (pstar - po)*entho
          
          cstar = sqrt(abs(gamco*pstar/rstar))
          cstar = max(cstar,csmall)
          
          
          spout = co - sgnm*uo
          spin = cstar - sgnm*ustar
          
          ushock = 0.5d0*(spin + spout)
          
          if (pstar-po .ge. 0.d0) then
             spin = ushock
             spout = ushock
          endif
          if (spout-spin .eq. 0.d0) then
             scr = small*cav(i,j)
          else
             scr = spout-spin
          endif
          frac = (1.d0 + (spout + spin)/scr)*0.5d0
          frac = max(0.d0,min(1.d0,frac))

          ! the transverse velocity states only depend on the
          ! direction that the contact moves
          if (ustar .gt. 0.d0) then
             v1gdnv = v1l
             v2gdnv = v2l
          else if (ustar .lt. 0.d0) then
             v1gdnv = v1r
             v2gdnv = v2r
          else
             v1gdnv = 0.5d0*(v1l+v1r)
             v2gdnv = 0.5d0*(v2l+v2r)
          endif

          ! linearly interpolate between the star and normal state -- this covers the
          ! case where we are inside the rarefaction fan.
          rgdnv = frac*rstar + (1.d0 - frac)*ro          
          ugdnv(i,j,kc) = frac*ustar + (1.d0 - frac)*uo
          pgdnv(i,j,kc) = frac*pstar + (1.d0 - frac)*po
          !regdnv = frac*estar + (1.d0 - frac)*reo
          gamgdnv =  frac*gamstar + (1.d0-frac)*gameo          

          ! now handle the cases where instead we are fully in the
          ! star or fully in the original (l/r) state
          if (spout .lt. 0.d0) then
             rgdnv = ro
             ugdnv(i,j,kc) = uo
             pgdnv(i,j,kc) = po
             !regdnv = reo
             gamgdnv = gameo
          endif
          if (spin .ge. 0.d0) then
             rgdnv = rstar
             ugdnv(i,j,kc) = ustar
             pgdnv(i,j,kc) = pstar
             !regdnv = estar
             gamgdnv = gamstar
          endif

          
          pgdnv(i,j,kc) = max(pgdnv(i,j,kc),small_pres)

          ! Enforce that fluxes through a symmetry plane are hard zero.
          if (i    .eq.0 .and. physbc_lo(1) .eq. Symmetry .and. idir .eq. 1) &
               ugdnv(i,j,kc) = 0.d0
          if (j    .eq.0 .and. physbc_lo(2) .eq. Symmetry .and. idir .eq. 2) &
               ugdnv(i,j,kc) = 0.d0
          if (kflux.eq.0 .and. physbc_lo(3) .eq. Symmetry .and. idir .eq. 3) &
               ugdnv(i,j,kc) = 0.d0
          
          ! Compute fluxes, order as conserved state (not q)
          uflx(i,j,kflux,URHO) = rgdnv*ugdnv(i,j,kc)
          
          if(idir.eq.1) then
             uflx(i,j,kflux,UMX) = uflx(i,j,kflux,URHO)*ugdnv(i,j,kc) + pgdnv(i,j,kc)
             uflx(i,j,kflux,UMY) = uflx(i,j,kflux,URHO)*v1gdnv
             uflx(i,j,kflux,UMZ) = uflx(i,j,kflux,URHO)*v2gdnv
          elseif(idir.eq.2) then
             uflx(i,j,kflux,UMX) = uflx(i,j,kflux,URHO)*v1gdnv
             uflx(i,j,kflux,UMY) = uflx(i,j,kflux,URHO)*ugdnv(i,j,kc) + pgdnv(i,j,kc)
             uflx(i,j,kflux,UMZ) = uflx(i,j,kflux,URHO)*v2gdnv
          else
             uflx(i,j,kflux,UMX) = uflx(i,j,kflux,URHO)*v1gdnv
             uflx(i,j,kflux,UMY) = uflx(i,j,kflux,URHO)*v2gdnv
             uflx(i,j,kflux,UMZ) = uflx(i,j,kflux,URHO)*ugdnv(i,j,kc) + pgdnv(i,j,kc)
          endif

          ! this is an alternate way to deal with the energy, but it ignores the gamstar stuff
          !rhoetot = regdnv + 0.5d0*rgdnv*(ugdnv(i,j,kc)**2 + v1gdnv**2 + v2gdnv**2)
          !uflx(i,j,kflux,UEINT) = ugdnv(i,j,kc)*regdnv

          ! compute the total energy from the internal, p/(gamma - 1), and the kinetic
          rhoetot = pgdnv(i,j,kc)/(gamgdnv - 1.0d0) + &
               0.5d0*rgdnv*(ugdnv(i,j,kc)**2 + v1gdnv**2 + v2gdnv**2)

          uflx(i,j,kflux,UEDEN) = ugdnv(i,j,kc)*(rhoetot + pgdnv(i,j,kc))
          uflx(i,j,kflux,UEINT) = ugdnv(i,j,kc)*pgdnv(i,j,kc)/(gamgdnv - 1.d0)


          ! Treat K as a passively advected quantity but allow it to
          ! affect fluxes of (rho E) and momenta.
          if (UESGS .gt. -1) then
             n  = UESGS
             nq = QESGS
             if (ustar .gt. 0.d0) then
                qavg = ql(i,j,kc,nq)
             else if (ustar .lt. 0.d0) then
                qavg = qr(i,j,kc,nq)
             else
                qavg = 0.5d0 * (ql(i,j,kc,nq) + qr(i,j,kc,nq))
             endif
             
             uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qavg
             
             rho_K_contrib =  twothirds * rgdnv * qavg
             
             if(idir.eq.1) then
                uflx(i,j,kflux,UMX) = uflx(i,j,kflux,UMX) + rho_K_contrib
             elseif(idir.eq.2) then
                uflx(i,j,kflux,UMY) = uflx(i,j,kflux,UMY) + rho_K_contrib
             elseif(idir.eq.3) then
                uflx(i,j,kflux,UMZ) = uflx(i,j,kflux,UMZ) + rho_K_contrib
             endif
             
             uflx(i,j,kflux,UEDEN) = uflx(i,j,kflux,UEDEN) + ugdnv(i,j,kc) * rho_K_contrib
          end if

          ! advected quantities -- only the contact matters
          do iadv = 1, nadv
             n  = UFA + iadv - 1
             nq = QFA + iadv - 1
             if (ustar .gt. 0.d0) then
                uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*ql(i,j,kc,nq)
             else if (ustar .lt. 0.d0) then
                uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qr(i,j,kc,nq)
             else
                qavg = 0.5d0 * (ql(i,j,kc,nq) + qr(i,j,kc,nq))
                uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qavg
             endif
          enddo
          
          ! species -- only the contact matters
          do ispec = 1, nspec
             n  = UFS + ispec - 1
             nq = QFS + ispec - 1
             if (ustar .gt. 0.d0) then
                uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*ql(i,j,kc,nq)
             else if (ustar .lt. 0.d0) then
                uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qr(i,j,kc,nq)
             else
                qavg = 0.5d0 * (ql(i,j,kc,nq) + qr(i,j,kc,nq))
                uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qavg
             endif
          enddo
          
          ! auxillary quantities -- only the contact matters
          do iaux = 1, naux
             n  = UFX + iaux - 1
             nq = QFX + iaux - 1
             if (ustar .gt. 0.d0) then
                uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*ql(i,j,kc,nq)
             else if (ustar .lt. 0.d0) then
                uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qr(i,j,kc,nq)
             else
                qavg = 0.5d0 * (ql(i,j,kc,nq) + qr(i,j,kc,nq))
                uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qavg
             endif
          enddo
          
       enddo
    enddo

  end subroutine riemanncg

  subroutine wsqge(p,v,gam,gdot,gstar,pstar,wsq,csq,gmin,gmax)

    double precision p,v,gam,gdot,gstar,pstar,wsq,csq,gmin,gmax
    double precision smlp1,small,divide,temp

    data smlp1,small/.001d0,1.d-07/

    ! First predict a value of game across the shock

    ! CG Eq. 31
    gstar=(pstar-p)*gdot/(pstar+p) + gam
    gstar=max(gmin,min(gmax,gstar))

    ! Now use that predicted value of game with the R-H jump conditions
    ! to compute the wave speed.

    ! CG Eq. 34
    wsq = (0.5d0*(gstar-1.0d0)*(pstar+p)+pstar)
    temp = ((gstar-gam)/(gam-1.0d0))

    if (pstar-p.eq.0.0d0) then
       divide=small
    else
       divide=pstar-p
    endif
    
    temp=temp/divide
    wsq = wsq/(v - temp*p*v)
    if (abs(pstar/p-1.d0)-smlp1 .lt. 0.0d0 ) then
       wsq = csq
    endif
    wsq=max(wsq,(.5d0*(gam-1.d0)/gam)*csq)
    
    return
  end subroutine wsqge

! ::: 
! ::: ------------------------------------------------------------------
! ::: 

      subroutine riemannus(ql,qr,qpd_l1,qpd_l2,qpd_l3,qpd_h1,qpd_h2,qpd_h3, &
                           gamcl,gamcr,cav,smallc,gd_l1,gd_l2,gd_h1,gd_h2, &
                           uflx,uflx_l1,uflx_l2,uflx_l3,uflx_h1,uflx_h2,uflx_h3, &
                           ugdnv,pgdnv,pg_l1,pg_l2,pg_l3,pg_h1,pg_h2,pg_h3, &
                           idir,ilo,ihi,jlo,jhi,kc,kflux)

      use network, only : nspec, naux
      use prob_params_module, only : physbc_lo,Symmetry
      use meth_params_module, only : QVAR, NVAR, QRHO, QU, QV, QW, QPRES, QREINT, QESGS, QFA, QFS, &
                                     QFX, URHO, UMX, UMY, UMZ, UEDEN, UEINT, UESGS, UFA, UFS, UFX, &
                                     nadv, small_dens, small_pres

      implicit none
      double precision, parameter:: small = 1.d-8
      double precision, parameter:: twothirds = 2.d0/3.d0

      integer qpd_l1,qpd_l2,qpd_l3,qpd_h1,qpd_h2,qpd_h3
      integer gd_l1,gd_l2,gd_h1,gd_h2
      integer uflx_l1,uflx_l2,uflx_l3,uflx_h1,uflx_h2,uflx_h3
      integer pg_l1,pg_l2,pg_l3,pg_h1,pg_h2,pg_h3
      integer idir,ilo,ihi,jlo,jhi
      integer i,j,kc,kflux

      double precision ql(qpd_l1:qpd_h1,qpd_l2:qpd_h2,qpd_l3:qpd_h3,QVAR)
      double precision qr(qpd_l1:qpd_h1,qpd_l2:qpd_h2,qpd_l3:qpd_h3,QVAR)
      double precision  gamcl(gd_l1:gd_h1,gd_l2:gd_h2)
      double precision  gamcr(gd_l1:gd_h1,gd_l2:gd_h2)
      double precision    cav(gd_l1:gd_h1,gd_l2:gd_h2)
      double precision smallc(gd_l1:gd_h1,gd_l2:gd_h2)
      double precision uflx(uflx_l1:uflx_h1,uflx_l2:uflx_h2,uflx_l3:uflx_h3,NVAR)
      double precision ugdnv(pg_l1:pg_h1,pg_l2:pg_h2,pg_l3:pg_h3)
      double precision pgdnv(pg_l1:pg_h1,pg_l2:pg_h2,pg_l3:pg_h3)

      integer n, nq
      integer iadv, ispec, iaux

      double precision rgdnv,v1gdnv,v2gdnv,regdnv,ustar
      double precision rl, ul, v1l, v2l, pl, rel
      double precision rr, ur, v1r, v2r, pr, rer
      double precision wl, wr, rhoetot, scr
      double precision rstar, cstar, estar, pstar
      double precision ro, uo, po, reo, co, gamco, entho
      double precision sgnm, spin, spout, ushock, frac
      double precision wsmall, csmall,qavg
      double precision rho_K_contrib

      !$OMP PARALLEL DO PRIVATE(i,j,rl,ul,v1l,v2l,pl,rel,rr,ur,v1r,v2r,pr,rer,csmall,wsmall,wl,wr,pstar,ustar,ro,uo) &
      !$OMP PRIVATE(po,reo,gamco,co,entho,rstar,estar,cstar,sgnm,spout,spin,ushock,scr,frac,v1gdnv,v2gdnv,rgdnv,regdnv) &
      !$OMP PRIVATE(rhoetot,iadv,n,nq,qavg,ispec,iaux,rho_K_contrib)
      do j = jlo, jhi
         do i = ilo, ihi

            rl = max(ql(i,j,kc,QRHO),small_dens)

            ! pick left velocities based on direction
            if(idir.eq.1) then
               ul  = ql(i,j,kc,QU)
               v1l = ql(i,j,kc,QV)
               v2l = ql(i,j,kc,QW)
            elseif(idir.eq.2) then
               ul  = ql(i,j,kc,QV)
               v1l = ql(i,j,kc,QU)
               v2l = ql(i,j,kc,QW)
            else
               ul  = ql(i,j,kc,QW)
               v1l = ql(i,j,kc,QU)
               v2l = ql(i,j,kc,QV)
            endif

            pl  = max(ql(i,j,kc,QPRES ),small_pres)
            rel =     ql(i,j,kc,QREINT)

            rr = max(qr(i,j,kc,QRHO),small_dens)

            ! pick right velocities based on direction
            if(idir.eq.1) then
               ur  = qr(i,j,kc,QU)
               v1r = qr(i,j,kc,QV)
               v2r = qr(i,j,kc,QW)
            elseif(idir.eq.2) then
               ur  = qr(i,j,kc,QV)
               v1r = qr(i,j,kc,QU)
               v2r = qr(i,j,kc,QW)
            else
               ur  = qr(i,j,kc,QW)
               v1r = qr(i,j,kc,QU)
               v2r = qr(i,j,kc,QV)
            endif

            pr  = max(qr(i,j,kc,QPRES),small_pres)
            rer =     qr(i,j,kc,QREINT)

            csmall = smallc(i,j)
            wsmall = small_dens*csmall
            wl = max(wsmall,sqrt(abs(gamcl(i,j)*pl*rl)))
            wr = max(wsmall,sqrt(abs(gamcr(i,j)*pr*rr)))

            pstar = ((wr*pl + wl*pr) + wl*wr*(ul - ur))/(wl + wr)
            ustar = ((wl*ul + wr*ur) + (pl - pr))/(wl + wr)
            pstar = max(pstar,small_pres)

            if (ustar .gt. 0.d0) then
               ro = rl
               uo = ul
               po = pl
               reo = rel
               gamco = gamcl(i,j)
            else if (ustar .lt. 0.d0) then
               ro = rr
               uo = ur
               po = pr
               reo = rer
               gamco = gamcr(i,j)
            else
               ro = 0.5d0*(rl+rr)
               uo = 0.5d0*(ul+ur)
               po = 0.5d0*(pl+pr)
               reo = 0.5d0*(rel+rer)
               gamco = 0.5d0*(gamcl(i,j)+gamcr(i,j))
            endif
            ro = max(small_dens,ro)
         
            co = sqrt(abs(gamco*po/ro))
            co = max(csmall,co)
            entho = (reo/ro + po/ro)/co**2
            rstar = ro + (pstar - po)/co**2
            rstar = max(small_dens,rstar)
            estar = reo + (pstar - po)*entho
            cstar = sqrt(abs(gamco*pstar/rstar))
            cstar = max(cstar,csmall)

            sgnm = sign(1.d0,ustar)
            spout = co - sgnm*uo
            spin = cstar - sgnm*ustar
            ushock = 0.5d0*(spin + spout)
            if (pstar-po .ge. 0.d0) then
               spin = ushock
               spout = ushock
            endif
            if (spout-spin .eq. 0.d0) then
               scr = small*cav(i,j)
            else
               scr = spout-spin
            endif
            frac = (1.d0 + (spout + spin)/scr)*0.5d0
            frac = max(0.d0,min(1.d0,frac))

            if (ustar .gt. 0.d0) then
               v1gdnv = v1l
               v2gdnv = v2l
            else if (ustar .lt. 0.d0) then
               v1gdnv = v1r
               v2gdnv = v2r
            else
               v1gdnv = 0.5d0*(v1l+v1r)
               v2gdnv = 0.5d0*(v2l+v2r)
            endif
            rgdnv = frac*rstar + (1.d0 - frac)*ro

            ugdnv(i,j,kc) = frac*ustar + (1.d0 - frac)*uo
            pgdnv(i,j,kc) = frac*pstar + (1.d0 - frac)*po

            regdnv = frac*estar + (1.d0 - frac)*reo
            if (spout .lt. 0.d0) then
               rgdnv = ro
               ugdnv(i,j,kc) = uo
               pgdnv(i,j,kc) = po
               regdnv = reo
            endif
            if (spin .ge. 0.d0) then
               rgdnv = rstar
               ugdnv(i,j,kc) = ustar
               pgdnv(i,j,kc) = pstar
               regdnv = estar
            endif

            pgdnv(i,j,kc) = max(pgdnv(i,j,kc),small_pres)

            ! Enforce that fluxes through a symmetry plane are hard zero.
            if (i    .eq.0 .and. physbc_lo(1) .eq. Symmetry .and. idir .eq. 1) &
                 ugdnv(i,j,kc) = 0.d0
            if (j    .eq.0 .and. physbc_lo(2) .eq. Symmetry .and. idir .eq. 2) &
                 ugdnv(i,j,kc) = 0.d0
            if (kflux.eq.0 .and. physbc_lo(3) .eq. Symmetry .and. idir .eq. 3) &
                 ugdnv(i,j,kc) = 0.d0

            ! Compute fluxes, order as conserved state (not q)
            uflx(i,j,kflux,URHO) = rgdnv*ugdnv(i,j,kc)

            if(idir.eq.1) then
               uflx(i,j,kflux,UMX) = uflx(i,j,kflux,URHO)*ugdnv(i,j,kc) + pgdnv(i,j,kc)
               uflx(i,j,kflux,UMY) = uflx(i,j,kflux,URHO)*v1gdnv
               uflx(i,j,kflux,UMZ) = uflx(i,j,kflux,URHO)*v2gdnv
            elseif(idir.eq.2) then
               uflx(i,j,kflux,UMX) = uflx(i,j,kflux,URHO)*v1gdnv
               uflx(i,j,kflux,UMY) = uflx(i,j,kflux,URHO)*ugdnv(i,j,kc) + pgdnv(i,j,kc)
               uflx(i,j,kflux,UMZ) = uflx(i,j,kflux,URHO)*v2gdnv
            else
               uflx(i,j,kflux,UMX) = uflx(i,j,kflux,URHO)*v1gdnv
               uflx(i,j,kflux,UMY) = uflx(i,j,kflux,URHO)*v2gdnv
               uflx(i,j,kflux,UMZ) = uflx(i,j,kflux,URHO)*ugdnv(i,j,kc) + pgdnv(i,j,kc)
            endif

            rhoetot = regdnv + 0.5d0*rgdnv*(ugdnv(i,j,kc)**2 + v1gdnv**2 + v2gdnv**2)

            uflx(i,j,kflux,UEDEN) = ugdnv(i,j,kc)*(rhoetot + pgdnv(i,j,kc))
            uflx(i,j,kflux,UEINT) = ugdnv(i,j,kc)*regdnv

            ! Treat K as a passively advected quantity but allow it to affect fluxes of (rho E) and momenta.
            if (UESGS .gt. -1) then
               n  = UESGS
               nq = QESGS
               if (ustar .gt. 0.d0) then
                  qavg = ql(i,j,kc,nq)
               else if (ustar .lt. 0.d0) then
                  qavg = qr(i,j,kc,nq)
               else
                  qavg = 0.5d0 * (ql(i,j,kc,nq) + qr(i,j,kc,nq))
               endif
    
               uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qavg
 
               rho_K_contrib =  twothirds * rgdnv * qavg
 
               if(idir.eq.1) then
                  uflx(i,j,kflux,UMX) = uflx(i,j,kflux,UMX) + rho_K_contrib
               elseif(idir.eq.2) then
                  uflx(i,j,kflux,UMY) = uflx(i,j,kflux,UMY) + rho_K_contrib
               elseif(idir.eq.3) then
                  uflx(i,j,kflux,UMZ) = uflx(i,j,kflux,UMZ) + rho_K_contrib
               endif
 
               uflx(i,j,kflux,UEDEN) = uflx(i,j,kflux,UEDEN) + ugdnv(i,j,kc) * rho_K_contrib
            end if

            do iadv = 1, nadv
               n  = UFA + iadv - 1
               nq = QFA + iadv - 1
               if (ustar .gt. 0.d0) then
                  uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*ql(i,j,kc,nq)
               else if (ustar .lt. 0.d0) then
                  uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qr(i,j,kc,nq)
               else
                  qavg = 0.5d0 * (ql(i,j,kc,nq) + qr(i,j,kc,nq))
                  uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qavg
               endif
            enddo

            do ispec = 1, nspec
               n  = UFS + ispec - 1
               nq = QFS + ispec - 1
               if (ustar .gt. 0.d0) then
                  uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*ql(i,j,kc,nq)
               else if (ustar .lt. 0.d0) then
                  uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qr(i,j,kc,nq)
               else
                  qavg = 0.5d0 * (ql(i,j,kc,nq) + qr(i,j,kc,nq))
                  uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qavg
               endif
            enddo

            do iaux = 1, naux
               n  = UFX + iaux - 1
               nq = QFX + iaux - 1
               if (ustar .gt. 0.d0) then
                  uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*ql(i,j,kc,nq)
               else if (ustar .lt. 0.d0) then
                  uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qr(i,j,kc,nq)
               else
                  qavg = 0.5d0 * (ql(i,j,kc,nq) + qr(i,j,kc,nq))
                  uflx(i,j,kflux,n) = uflx(i,j,kflux,URHO)*qavg
               endif
            enddo
         
         enddo
      enddo
      !$OMP END PARALLEL DO

      end subroutine riemannus

end module riemann_module
