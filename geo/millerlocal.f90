module millerlocal

  use common_types, only: flux_surface_type

  implicit none

  public :: init_local_defaults
  public :: read_local_parameters
  public :: get_local_geo
  public :: local
!  public :: Rpos, Zpos

  private

  integer :: nzed_local
  real :: rhoc, rmaj, shift
  real :: kappa, kapprim
  real :: tri, triprim
  real :: betaprim, betadbprim
  real :: qinp, shat, d2qdr2
  real :: rgeo
  real :: d2psidr2
  real :: rhotor, drhotordrho
  logical :: write_profile_variation, read_profile_variation

  integer :: nz, nz2pi

  real :: bi, dqdr, d2Idr2
  real, dimension (:), allocatable :: grho, bmag, gradpar
  real, dimension (:), allocatable :: gds2, gds21, gds22
  real, dimension (:), allocatable :: gds23, gds24
  real, dimension (:), allocatable :: gbdrift0, gbdrift
  real, dimension (:), allocatable :: cvdrift0, cvdrift
  real, dimension (:), allocatable :: d2Rdth2, d2Zdth2, d2Rdrdth, d2Zdrdth
  real, dimension (:), allocatable :: gpsi, dBdrho, d2Bdrdth
  real, dimension (:), allocatable :: dgradpardrho, dgradparBdrho, dBdth, gradparb
  real, dimension (:), allocatable :: dcvdrift0drho, dgbdrift0drho, theta, thetatot
  real, dimension (:), allocatable :: varthet, dvarthdr, gradrho_gradthet, cross, d2varthdr2
  real, dimension (:), allocatable :: gradthet2, gradalph_gradthet, gradrho_gradalph, gradalph2
  real, dimension (:), allocatable :: d2Bdr2, d2Rdr2, d2Zdr2, drz, drzdth
  real, dimension (:), allocatable :: d2Rdr2dth, d2Zdr2dth, d2gpsidr2, dcrossdr
  real, dimension (:), allocatable :: dcvdriftdrho, dgbdriftdrho, dgds2dr, dgds21dr, dgds22dr
  real, dimension (:), allocatable :: dgr2dr, dgpsi2dr
  real, dimension (:), allocatable :: dgrgt, dgt2, dgagr, dgagt, dga2
  real, dimension (:,:), allocatable :: Rr, Zr

  real, dimension (:), allocatable :: jacrho, delthet, djacdrho, djacrdrho
  real, dimension (:), allocatable :: d2jacdr2, dRdrho, dZdrho, dRdth, dZdth

  real, dimension (:), allocatable :: d2R, d2Z

  type (flux_surface_type) :: local

  logical :: defaults_initialized = .false.

contains

  subroutine init_local_defaults

    implicit none

    if (defaults_initialized) return
    defaults_initialized = .true.

    nzed_local = 128
    rhoc = 0.5
    rmaj = 3.0
    rgeo = 3.0
    qinp = 1.4
    shat = 0.8
    shift = 0.0
    kappa = 0.0
    kapprim = 0.0
    tri = 0.0
    triprim = 0.0
    ! betaprim = -(4pi/Bref^2)*d(ptot)/drho
    betaprim = 0.0
    ! betadbprim = -(4pi/Bref^2)*d^2ptot/drho^2
    betadbprim = 0.0
    d2qdr2 = 0.0
    d2psidr2 = 0.0
    read_profile_variation = .false.
    write_profile_variation = .false.
    
    ! only needed for sfincs when not using 
    ! geo info from file
    rhotor = rhoc
    drhotordrho = 1.0

  end subroutine init_local_defaults

  subroutine read_local_parameters (local_out)
    
    use file_utils, only: input_unit_exist
    use common_types, only: flux_surface_type

    implicit none
 
    type (flux_surface_type), intent (out) :: local_out

    integer :: in_file
    logical :: exist

    namelist /millergeo_parameters/ rhoc, rmaj, shift, qinp, shat, &
         kappa, kapprim, tri, triprim, rgeo, betaprim, &
         betadbprim, d2qdr2, d2psidr2, &
         nzed_local, read_profile_variation, write_profile_variation
    
    call init_local_defaults

    in_file = input_unit_exist("millergeo_parameters", exist)
    if (exist) read (unit=in_file, nml=millergeo_parameters)

    local%rhoc = rhoc
    local%rmaj = rmaj
    local%rgeo = rgeo
    local%shift = shift
    local%kappa = kappa
    local%kapprim = kapprim
    local%qinp = qinp
    local%shat = shat
    local%tri = tri
    local%triprim = triprim
    local%betaprim = betaprim
    local%betadbprim = betadbprim
    local%d2qdr2 = d2qdr2
    local%d2psidr2 = d2psidr2

    ! following two variables are not inputs
    local%dr = 1.e-3
    local%rhotor = rhotor
    local%drhotordrho = drhotordrho
    local%dpsitordrho = 0.0
    local%d2psitordrho2 = 0.0

    local_out = local

  end subroutine read_local_parameters

  subroutine get_local_geo (nzed, nzgrid, zed_in, &
       dpsidrho, dIdrho, grho_out, bmag_out, &
       gds2_out, gds21_out, gds22_out, gds23_out, gds24_out, gradpar_out, &
       gbdrift0_out, gbdrift_out, cvdrift0_out, cvdrift_out, &
       dBdrho_out, d2Bdrdth_out, dgradpardrho_out, &
       btor_out, rmajor_out)
    
    use constants, only: pi
    use splines, only: geo_spline

    implicit none

    integer, intent (in) :: nzed, nzgrid
    real, dimension (-nzgrid:), intent (in) :: zed_in
    real, intent (out) :: dpsidrho, dIdrho
    real, dimension (-nzgrid:), intent (out) :: grho_out, bmag_out, &
         gds2_out, gds21_out, gds22_out, gds23_out, gds24_out, &
         gradpar_out, gbdrift0_out, &
         gbdrift_out, cvdrift0_out, cvdrift_out, &
         dBdrho_out, d2Bdrdth_out, dgradpardrho_out, &
         btor_out, rmajor_out

    integer :: nr, np
    integer :: i, j
    real :: rmin
    real, dimension (3) :: dr

    ! number of grid points used for radial derivatives
    nr = 3

    ! first get nperiod corresponding to input number of grid points
    nz2pi = nzed/2
    np = (nzgrid-nz2pi)/nzed + 1

    ! now switch to using (possible higher resolution) local grid
    nz2pi = nzed_local/2
    ! this is the equivalent of nzgrid on the local grid
    nz = nz2pi + nzed_local*(np-1)

    dqdr = local%shat*local%qinp/local%rhoc
    call allocate_arrays (nr, nz)

    dr(1) = -local%dr
    dr(2) = 0.
    dr(3) = local%dr

    ! initialize to zero
    ! will be overwritten if reading in from file
    ! only relevant for profile variation tests
    d2R = 0. ; d2Z = 0.
    
    if (read_profile_variation) then
       open (1002,file='RZ.in',status='old')
       do j=-nz,nz
          read (1002,'(3e13.5)') theta(j), d2R(j), d2Z(j)
       end do
       close (1002)
    end if
    
    do j=-nz,nz
       theta(j) = j*(2*np-1)*pi/real(nz)
       do i=1,3
          rmin = local%rhoc + dr(i)
          Rr(i,j) = Rpos(rmin,theta(j),j)
          Zr(i,j) = Zpos(rmin,theta(j),j)
       end do
    end do

    allocate (delthet(-nz:nz-1))
    ! get delta theta as a function of theta
    delthet = theta(-nz+1:)-theta(:nz-1)

    ! get dR/drho and dZ/drho
    call get_drho (Rr, dRdrho)
    call get_drho (Zr, dZdrho)

    ! get dR/dtheta and dZ/dtheta
    call get_dthet(Rr(2,:), dRdth)
    call get_dthet(Zr(2,:), dZdth)

    ! get second derivatives of R and Z with respect to theta
    call get_d2dthet2 (Rr(2,:), d2Rdth2)
    call get_d2dthet2 (Zr(2,:), d2Zdth2)
    ! get mixed theta and rho derivatives of R and Z
    call get_dthet (dRdrho, d2Rdrdth)
    call get_dthet (dZdrho, d2Zdrdth)

    ! get the Jacobian of the transformation from (rho,theta,zeta) to (R,Z,zeta)
    ! this is what I call jacr or jacrho in following comments
    ! as opposed to jacobian, which is for tranformation from (psi,theta,zeta) to (R,Z,zeta)
    call get_jacrho

    ! theta_integrate returns integral from 0 -> 2*pi
    ! note that dpsidrho here is an intermediary
    ! that requires manipulation to get final dpsidrho
    call theta_integrate (jacrho(-nz2pi:nz2pi)/Rr(2,-nz2pi:nz2pi)**2, dpsidrho)
    dpsidrho = dpsidrho/(2.*pi)

    ! get dpsinorm/drho = (I/2*pi*q)*int_0^{2*pi} dthet jacrho/R**2

    ! if using input.profiles, we are given
    ! dpsitordrho and must use it to compute rgeo
    if (abs(local%dpsitordrho) > epsilon(0.)) then
       local%rgeo = local%dpsitordrho/dpsidrho
       dpsidrho = local%dpsitordrho/local%qinp
       local%d2psidr2 = (local%d2psitordrho2-local%dpsitordrho*local%shat/local%rhoc) &
            / local%qinp
       ! I=Btor*R is a flux function
       ! bi = I/(Btor(psi,theta of Rgeo)*a) = Rgeo/a
       bi = local%rgeo
    else
       ! otherwise, we are given rgeo
       ! and must use it to compute dpsidrho

       ! I=Btor*R is a flux function
       ! bi = I/(Btor(psi,theta of Rgeo)*a) = Rgeo/a
       bi = local%rgeo
       dpsidrho = dpsidrho*bi/local%qinp
    end if

!    ! get dpsinorm/drho
!    call get_dpsidrho (dpsidrho)

    ! get |grad rho| and |grad psi|
    call get_gradrho (dpsidrho, grho)

    ! quantity needed in calculation of dI/drho and djacrho/drho
    drz = (dRdrho*dRdth + dZdrho*dZdth)/jacrho
    call get_dthet (drz, drzdth)

    ! get dI/drho
    call get_dIdrho (dpsidrho, grho, dIdrho)

    ! get djacobian/drho*dpsi/drho and djacr/drho
    call get_djacdrho (dpsidrho, dIdrho, grho)

    ! get d2R/drho2 and d2Z/drho2
    call get_d2RZdr2
    
    if (write_profile_variation) then
       open (1002,file='RZ.out',status='unknown')
       do j=-nz,nz
          write (1002,'(3e13.5)') theta(j), d2Rdr2(j), d2Zdr2(j)
       end do
       close (1002)
    end if
    
    ! get theta derivative of d2R/drho2 and d2Z/drho2
    call get_dthet (d2Rdr2, d2Rdr2dth)
    call get_dthet (d2Zdr2, d2Zdr2dth)

    ! calculate the magnitude of B (normalized by B(psi,theta corresponding to Rgeo))
    ! B/B0 = sqrt(I**2 + |grad psi|**2)/R
    bmag = sqrt(bi**2 + gpsi**2)/Rr(2,:)

    ! get dB/dtheta
    call get_dthet (bmag, dbdth)
    
    ! calculate b . grad theta
    gradpar = dpsidrho/(bmag*jacrho)
    ! b . grad B
    gradparb = gradpar*dBdth

    ! get d|grad rho|^2/drho and d|grad psi|^2/drho
    call get_dgr2dr (dpsidrho, grho)

    ! get dB/drho and d2B/drho2
    call get_dBdrho (bmag, dIdrho)

    ! d (b . grad theta) / drho
    dgradpardrho = -gradpar*(dBdrho/bmag + djacdrho/jacrho)

    ! get d/dtheta (dB/drho)
    call get_dthet (dBdrho, d2Bdrdth)
    
    ! d(b . grad B)/drho
    dgradparBdrho = dgradpardrho*dBdth + gradpar*d2Bdrdth

    ! obtain varthet = (I/(q*(dpsi/dr)) * int_0^theta dtheta' jacrho/R^2
    call get_varthet (dpsidrho)

    ! obtain dvarthet/drho
    call get_dvarthdr (dpsidrho, dIdrho)

    ! get |grad theta|^2, grad r . grad theta, grad alpha . grad theta, etc.
    call get_graddotgrad (dpsidrho, grho)

    call get_gds (dpsidrho, gds2, gds21, gds22, gds23, gds24)

    ! this is (grad alpha x B) . grad theta
    cross = dpsidrho*(gradrho_gradalph*gradalph_gradthet - gradalph2*gradrho_gradthet)

    ! this is bhat/B x (grad B) . grad alpha * 2 * dpsiN/drho
    gbdrift = 2.0*(-dBdrho + cross*dBdth*dpsidrho/bmag**2)/bmag
    ! this is bhat/B x (bhat . grad bhat) . grad alpha * 2 * dpsiN/drho
    ! this is assuming betaprim = 4*pi*ptot/B0^2 * (-d ln ptot / drho)
    cvdrift = (gbdrift + 2.0*local%betaprim/bmag**2)

    ! this is 2 *(bhat/B x grad B / B) . (grad q) * dpsiN/drho / (bhat . grad B)
    ! same as usual GS2 definition once bhat . grad B is added in below
    cvdrift0 = -2.*bi*dqdr/bmag**2

    ! this is 2*dpsiN/drho times the rho derivative (bhat/B x grad B / B) . (grad q)
    dcvdrift0drho = cvdrift0*(dgradparbdrho + gradparb*(dIdrho/bi - 2.*dBdrho/bmag - local%d2psidr2/dpsidrho)) &
         - 2.*bi*gradparb*local%d2qdr2/bmag**2
    ! this is 2*dpsiN/drho times the rho derivative of (bhat x gradB/B) . (grad q)
    dgbdrift0drho = cvdrift0*bmag*(dgradparbdrho + gradparb*(dIdrho/bi - dBdrho/bmag - local%d2psidr2/dpsidrho)) &
         - 2.*bi*gradparb*local%d2qdr2/bmag

    cvdrift0 = cvdrift0*gradparb
    ! this is 2 * dpsiN/drho * (bhat/B x gradB/B) . (grad q)
!    gbdrift0 = cvdrift0*bmag
    gbdrift0 = cvdrift0

    ! get d^2I/drho^2 and d^2 Jac / dr^2
    call get_d2Idr2_d2jacdr2 (grho, dIdrho)

    ! get d^2varhteta/drho^2
    call get_d2varthdr2 (dpsidrho, dIdrho)

    ! get d2B/drho^2
    call get_d2Bdr2 (bmag, dIdrho)

    ! get d/dr [(grad alpha x B) . grad theta]
    call get_dcrossdr (dpsidrho, dIdrho, grho)

    ! dgbdriftdrho is d/drho (bhat/B x (grad B) . grad alpha) * 2 * dpsiN/drho
    dgbdriftdrho = 2.0*(local%d2psidr2*dBdrho/dpsidrho - d2Bdr2 &
         + dpsidrho*(dcrossdr*dBdth+cross*(d2Bdrdth-2.*dBdth*dBdrho/bmag))/bmag**2)
    ! dcvdriftdrho is d/drho (bhat/B x [bhat . grad bhat] . grad alpha) * 2 * dpsiN/drho
    ! shoudl check gbdrift term below
!    dcvdriftdrho = (dgbdriftdrho - gbdrift*dBdrho/bmag)/bmag &
    dcvdriftdrho = (dgbdriftdrho - gbdrift*dBdrho)/bmag &
         + 2.0*local%betadbprim/bmag**2 - 4.0*local%betaprim*dBdrho/bmag**3 &
         - 2.0*local%betaprim*local%d2psidr2/dpsidrho

    ! interpolate here
    call geo_spline (theta, grho, zed_in, grho_out)
    call geo_spline (theta, bmag, zed_in, bmag_out)
    call geo_spline (theta, gds2, zed_in, gds2_out)
    call geo_spline (theta, gds21, zed_in, gds21_out)
    call geo_spline (theta, gds22, zed_in, gds22_out)
    call geo_spline (theta, gds21, zed_in, gds23_out)
    call geo_spline (theta, gds21, zed_in, gds24_out)
    call geo_spline (theta, gradpar, zed_in, gradpar_out)
    call geo_spline (theta, gbdrift, zed_in, gbdrift_out)
    call geo_spline (theta, gbdrift0, zed_in, gbdrift0_out)
    call geo_spline (theta, cvdrift, zed_in, cvdrift_out)
    call geo_spline (theta, cvdrift0, zed_in, cvdrift0_out)
    call geo_spline (theta, dBdrho, zed_in, dBdrho_out)
    call geo_spline (theta, d2Bdrdth, zed_in, d2Bdrdth_out)
    call geo_spline (theta, dgradpardrho, zed_in, dgradpardrho_out)
    call geo_spline (theta, Rr(2,:), zed_in, rmajor_out)

    ! get the toroidal component of the magnetic field
    ! btor = B_toroidal/Bref = I/R Bref = rgeo * a/R
    btor_out = bi/rmajor_out

    open (1002,file='millerlocal.input',status='unknown')
    write (1002,'(5a16)') '#1.rhoc', '2.rmaj', '3.rgeo', '4.shift', '5.qinp'
    write (1002,'(5e16.8)') local%rhoc, local%rmaj, local%rgeo, local%shift, local%qinp
    write (1002,*)
    write (1002,'(5a16)') '#6.shat', '7.kappa', '8.kapprim', '9.tri', '10.triprim'
    write (1002,'(5e16.8)') local%shat, local%kappa, local%kapprim, local%tri, local%triprim
    write (1002,*)
    write (1002,'(5a16)') '11.betaprim', '12.dpsitordrho', '13.rhotor', &
         '14.drhotordrho', '15.d2qdr2'
    write (1002,'(5e16.8)') local%betaprim, local%dpsitordrho, local%rhotor, &
         local%drhotordrho, local%d2qdr2
    write (1002,*)
    write (1002,'(2a16)') '16.d2psidr2', '17.betadbprim'
    write (1002,'(2e16.8)') local%d2psidr2, local%betadbprim
    close (1002)

    open (1001,file='millerlocal.output',status='unknown')
    write (1001,'(a9,e12.4,a11,e12.4,a11,e12.4)') '#dI/dr: ', dIdrho, 'd2I/dr2: ', d2Idr2, 'dpsi/dr: ', dpsidrho
    write (1001,'(57a13)') '#1.theta', '2.R', '3.dR/dr', '4.d2Rdr2', '5.dR/dth', &
         '6.d2Rdrdth', '7.dZ/dr', '8.d2Zdr2', '9.dZ/dth', '10.d2Zdrdth', &
         '11.bmag', '12.dBdr', '13.d2Bdr2', '14.dB/dth', '15.d2Bdrdth', &
         '16.varthet', '17.dvarthdr', '18.d2varthdr2', '19.jacr', '20.djacrdr', &
         '21.djacdrho', '22.d2jacdr2', '23.grho2', '24.dgr2dr', '25.gthet2', &
         '26.dgt2', '27.grgthet', '28.dgrgt', '29.galphgth', '30.dgagt', &
         '31.grgalph', '32.dgagr', '33.galph2', '34.dga2', '35.cross', &
         '36.dcrossdr', '37.gbdrift0', '38.dgbdrift0', '39.cvdrift0', '40.dcvdrift0', &
         '41.gbdrift', '42.dgbdrift', '43.cvdrift', '44.dcvdrift', '45.drzdth', &
         '46.gradpar', '47.dgpardr', '48.gradparB', '49.dgparBdr', '50.gds2', &
         '51.dgds2dr', '52.gds21', '53.dgds21dr', '54.gds22', '55.dgds22dr', &
         '56.gds23', '57.gds24'

    do i = -nz, nz
       write (1001,'(57e13.4)') theta(i), Rr(2,i),dRdrho(i), d2Rdr2(i), dRdth(i), &
            d2Rdrdth(i), dZdrho(i), d2Zdr2(i), dZdth(i), d2Zdrdth(i), &
            bmag(i), dBdrho(i), d2Bdr2(i), dBdth(i), d2Bdrdth(i), &
            varthet(i), dvarthdr(i), d2varthdr2(i), jacrho(i), djacrdrho(i), &
            djacdrho(i), d2jacdr2(i), grho(i)**2, dgr2dr(i), gradthet2(i), &
            dgt2(i), gradrho_gradthet(i), dgrgt(i), gradalph_gradthet(i), dgagt(i), &
            gradrho_gradalph(i), dgagr(i), gradalph2(i), dga2(i), cross(i), &
            dcrossdr(i), gbdrift0(i), dgbdrift0drho(i), cvdrift0(i), dcvdrift0drho(i), &
            gbdrift(i), dgbdriftdrho(i), cvdrift(i), dcvdriftdrho(i), drzdth(i), &
            gradpar(i), dgradpardrho(i), gradparB(i), dgradparBdrho(i), gds2(i), &
            dgds2dr(i), gds21(i), dgds21dr(i), gds22(i), dgds22dr(i), gds23(i), gds24(i)
    end do
    close (1001)

    call deallocate_arrays

    defaults_initialized = .false.

  end subroutine get_local_geo

  subroutine allocate_arrays (nr, nz)

    implicit none

    integer, intent (in) :: nr, nz

    ! periodic quantities can be computed on 2*pi grid and replicated
    allocate (grho(-nz:nz), bmag(-nz:nz), gradpar(-nz:nz))
    allocate (gds2(-nz:nz), gds21(-nz:nz), gds22(-nz:nz), gds23(-nz:nz), gds24(-nz:nz))
    allocate (gbdrift0(-nz:nz), gbdrift(-nz:nz))
    allocate (cvdrift0(-nz:nz), cvdrift(-nz:nz))
    allocate (Rr(nr,-nz:nz), Zr(nr,-nz:nz))
    allocate (jacrho(-nz:nz), djacdrho(-nz:nz), djacrdrho(-nz:nz), d2jacdr2(-nz:nz))
    allocate (d2Rdrdth(-nz:nz), d2Zdrdth(-nz:nz), gpsi(-nz:nz))
    allocate (dBdrho(-nz:nz), dgradpardrho(-nz:nz))
    allocate (d2Bdrdth(-nz:nz), dgradparBdrho(-nz:nz), dBdth(-nz:nz), gradparb(-nz:nz))
    allocate (dcvdrift0drho(-nz:nz), dgbdrift0drho(-nz:nz))
    allocate (theta(-nz:nz))
    allocate (dRdrho(-nz:nz), dZdrho(-nz:nz), dRdth(-nz:nz), dZdth(-nz:nz))
    allocate (gradrho_gradthet(-nz:nz), gradthet2(-nz:nz), dgr2dr(-nz:nz), dgpsi2dr(-nz:nz))
    allocate (dgrgt(-nz:nz), dgt2(-nz:nz), dgagr(-nz:nz), dgagt(-nz:nz), dga2(-nz:nz))
    allocate (d2Rdr2(-nz:nz), d2Zdr2(-nz:nz), d2Bdr2(-nz:nz))
    allocate (drz(-nz:nz), drzdth(-nz:nz), d2Rdr2dth(-nz:nz), d2Zdr2dth(-nz:nz))
    allocate (d2Rdth2(-nz:nz), d2Zdth2(-nz:nz))
    allocate (d2gpsidr2(-nz:nz))
!    allocate (dgds22dr(-nz:nz), gds2(-nz:nz), gds21(-nz:nz), gds22(-nz:nz))
    allocate (dgds22dr(-nz:nz))
    allocate (gradalph_gradthet(-nz:nz), gradalph2(-nz:nz), gradrho_gradalph(-nz:nz))
    allocate (dgds2dr(-nz:nz), dgds21dr(-nz:nz))
    allocate (dcvdriftdrho(-nz:nz), dgbdriftdrho(-nz:nz))
    allocate (varthet(-nz:nz), dvarthdr(-nz:nz), d2varthdr2(-nz:nz))
    allocate (cross(-nz:nz))
    allocate (dcrossdr(-nz:nz))
    allocate (d2R(-nz:nz), d2Z(-nz:nz))

  end subroutine allocate_arrays

  subroutine deallocate_arrays

    implicit none

    deallocate (grho)
    deallocate (bmag)
    deallocate (gradpar)
    deallocate (gds2)
    deallocate (gds21)
    deallocate (gds22)
    deallocate (gds23)
    deallocate (gds24)
    deallocate (gbdrift0)
    deallocate (gbdrift)
    deallocate (cvdrift0)
    deallocate (cvdrift)
    deallocate (Rr, Zr)
    deallocate (jacrho, djacdrho, djacrdrho, d2jacdr2)
    deallocate (d2Rdrdth, d2Zdrdth, gpsi)
    deallocate (dBdrho, dgradpardrho)
    deallocate (d2Bdrdth, dgradparBdrho, dBdth, gradparb)
    deallocate (dcvdrift0drho, dgbdrift0drho)
    deallocate (theta)
    deallocate (dRdrho, dZdrho, dRdth, dZdth)
    deallocate (gradrho_gradthet, gradthet2, dgr2dr, dgpsi2dr)
    deallocate (dgrgt, dgt2, dgagr, dgagt, dga2)
    deallocate (d2Rdr2, d2Zdr2, d2Bdr2)
    deallocate (drz, drzdth, d2Rdr2dth, d2Zdr2dth)
    deallocate (d2Rdth2, d2Zdth2)
    deallocate (d2gpsidr2)
    deallocate (dgds22dr)
    deallocate (gradalph_gradthet, gradalph2, gradrho_gradalph)
    deallocate (dgds2dr, dgds21dr)
    deallocate (dcvdriftdrho, dgbdriftdrho)
    deallocate (varthet, dvarthdr, d2varthdr2)
    deallocate (cross)
    deallocate (dcrossdr)
    deallocate (d2R, d2Z)

  end subroutine deallocate_arrays

  ! takes in f(r), with r given at three radial locations
  ! and returns df = df/dr at the middle radius
  subroutine get_drho (f, df)

    implicit none

    real, dimension (:,-nz:), intent (in) :: f
    real, dimension (-nz:), intent (out) :: df

    df = 0.5*(f(3,:)-f(1,:))/local%dr

  end subroutine get_drho

  ! given function f(theta), calculate second derivative
  ! of f with respect to theta
  ! second order accurate, with equal grid spacing assumed
  subroutine get_d2dthet2 (f, d2f)

    implicit none

    real, dimension (-nz:), intent (in) :: f
    real, dimension (-nz:), intent (out) :: d2f

    ! assuming equal grid spacing in theta here
    d2f(-nz+1:nz-1) = (f(:nz-2)-2.*f(-nz+1:nz-1)+f(-nz+2:))/delthet(-nz+1:nz-1)**2

    ! use periodicity at boundary
    d2f(-nz) = (f(nz-1)-2.*f(-nz)+f(-nz+1))/delthet(-nz+1)**2
    d2f(nz) = d2f(-nz)

  end subroutine get_d2dthet2

  ! given function f(theta:-pi->pi), calculate theta derivative
  ! second order accurate, with equal grid spacing assumed
  ! assumes periodic in theta -- may need to change this in future
  subroutine get_dthet (f, df)

    implicit none

    real, dimension (-nz:), intent (in) :: f
    real, dimension (-nz:), intent (out) :: df

    ! assuming equal grid spacing in theta here
    df(-nz+1:nz-1) = (f(-nz+2:)-f(:nz-2))/(delthet(:nz-2)+delthet(-nz+1:))

    ! use periodicity at boundary
    df(-nz) = (f(-nz+1)-f(nz-1))/(delthet(-nz)+delthet(nz-1))
    df(nz) = df(-nz)

  end subroutine get_dthet

  subroutine get_jacrho

    implicit none

    ! jacrho = R*(dR/drho * dZ/dtheta - dR/dtheta * dZ/drho)
    jacrho = Rr(2,:)*(dRdrho*dZdth - dRdth*dZdrho)

  end subroutine get_jacrho

!   ! get dpsinorm/drho = (I/2*pi*q)*int_0^{2*pi} dthet jacrho/R**2
!   subroutine get_dpsidrho (dpsidrho)

!     use constants, only: pi

!     implicit none
    
!     real, intent (out) :: dpsidrho

!     ! theta_integrate returns integral from 0 -> 2*pi
!     call theta_integrate (jacrho(-nz2pi:nz2pi)/Rr(2,-nz2pi:nz2pi)**2, dpsidrho)

!     ! integration done using trapezoidal rule
!     dpsidrho = dpsidrho*bi/(2.*pi*local%qinp)

!   end subroutine get_dpsidrho

  subroutine get_gradrho (dpsidrho, grho)

    implicit none

    real, intent (in) :: dpsidrho
    real, dimension (-nz:), intent (out) :: grho

    grho = Rr(2,:)*sqrt(dRdth**2 + dZdth**2)/jacrho
    gpsi = grho*dpsidrho

  end subroutine get_gradrho

  subroutine get_dIdrho (dpsidrho, grho, dIdrho)

    use constants, only: pi

    implicit none

    real, intent (in) :: dpsidrho
    real, dimension (-nz:), intent (in) :: grho
    real, intent (out) :: dIdrho

    real :: num1, num2, denom
    real, dimension (:), allocatable :: dum

    allocate (dum(-nz:nz)) ; dum = 0.

    dum = jacrho*( 1.0 + (bi/gpsi)**2 ) / Rr(2,:)**2
    call theta_integrate (dum(-nz2pi:nz2pi), denom)

    dum = jacrho*( 2.*dRdrho/Rr(2,:) + dqdr/local%qinp ) / Rr(2,:)**2
    call theta_integrate (dum(-nz2pi:nz2pi), num1)

    ! betaprim below is (4*pi*ptot/B0^2)*(-d ln ptot / drho)
    dum = ( -2.*(dRdth*d2Rdrdth + dZdth*d2Zdrdth)/jacrho &
         + drzdth + local%betaprim*jacrho/dpsidrho**2 ) / grho**2
    call theta_integrate (dum(-nz2pi:nz2pi), num2)

    dIdrho = bi*(num1 + num2)/denom

    deallocate (dum)

  end subroutine get_dIdrho

  subroutine get_djacdrho (dpsidrho, dIdrho, grho)

    implicit none

    real, intent (in) :: dpsidrho, dIdrho
    real, dimension (-nz:), intent (in) :: grho

    ! this is dpsi/dr * d/dr (jacobian)
    ! betaprim below is (4*pi*ptot/B0^2)*(-d ln ptot / drho)
    djacdrho = (Rr(2,:)/grho)**2*(2.*(dRdth*d2Rdrdth+dZdth*d2Zdrdth)/jacrho &
         - drzdth + jacrho*(bi*dIdrho/Rr(2,:)**2 - local%betaprim)/dpsidrho**2)

    ! this is d/dr (jacobian_r)
    djacrdrho = djacdrho + jacrho*local%d2psidr2/dpsidrho

  end subroutine get_djacdrho

  subroutine get_d2RZdr2

    implicit none

    ! get factor common to both d2R/drho2 and d2Z/drho2
    d2Rdr2 = ((djacrdrho-jacrho*dRdrho/Rr(2,:))/Rr(2,:) &
         - dRdrho*d2Zdrdth + dZdrho*d2Rdrdth)/(dRdth**2+dZdth**2)

    d2Zdr2 = -d2Rdr2*dRdth
    d2Rdr2 = d2Rdr2*dZdth

  end subroutine get_d2RZdr2

  subroutine get_dgr2dr (dpsidrho, grho)

    implicit none

    real, intent (in) :: dpsidrho
    real, dimension (-nz:), intent (in) :: grho

    dgr2dr = 2.*(grho**2*(dRdrho/Rr(2,:)-djacrdrho/jacrho) &
         + (Rr(2,:)/jacrho)**2*(dRdth*d2Rdrdth + d2Zdrdth*dZdth))

    dgpsi2dr = 2.*(gpsi**2*(dRdrho/Rr(2,:)-djacdrho/jacrho) &
         + (Rr(2,:)/jacrho)**2*(dRdth*d2Rdrdth + d2Zdrdth*dZdth)*dpsidrho**2)

  end subroutine get_dgr2dr

  subroutine get_graddotgrad (dpsidrho, grho)

    implicit none

    real, intent (in) :: dpsidrho
    real, dimension (-nz:), intent (in) :: grho

    ! grad theta . grad theta
    gradthet2 = (Rr(2,:)/jacrho)**2*(dRdrho**2 + dZdrho**2)
    ! grad rho . grad theta
    gradrho_gradthet = -(Rr(2,:)/jacrho)**2*(dRdrho*dRdth+dZdrho*dZdth)

    ! grad alpha . grad theta
    gradalph_gradthet = -(varthet*dqdr + local%qinp*dvarthdr)*gradrho_gradthet &
         - bi*jacrho/(dpsidrho*Rr(2,:)**2)*gradthet2
    ! grad rho . grad alpha
    gradrho_gradalph = -(varthet*dqdr + local%qinp*dvarthdr)*grho**2 &
         - bi*jacrho/(dpsidrho*Rr(2,:)**2)*gradrho_gradthet
    ! grad alpha . grad alpha
    gradalph2 = (1./Rr(2,:)**2) + ((varthet*dqdr+local%qinp*dvarthdr)*grho)**2 &
         + 2.*bi*jacrho*(varthet*dqdr+local%qinp*dvarthdr)*gradrho_gradthet/(dpsidrho*Rr(2,:)**2) &
         + (bi*jacrho/(dpsidrho*Rr(2,:)**2))**2*gradthet2

  end subroutine get_graddotgrad

  subroutine get_gds (dpsidrho, gds2, gds21, gds22, gds23, gds24)

    implicit none

    real, intent (in) :: dpsidrho
    real, dimension (-nz:), intent (out) :: gds2, gds21, gds22, gds23, gds24

    ! |grad alpha|^2 * (dpsiN/drho)^2 (dpsiN/drho factor accounts for ky normalization)
    gds2 = gradalph2*dpsidrho**2
    ! (grad q . grad alpha) * (dpsiN/drho)^2
    gds21 = gradrho_gradalph*dqdr*dpsidrho**2
    ! |grad q|^2 * (dpsiN/drho)^2
    gds22 = (gpsi*dqdr)**2
    ! (grad rho . grad theta * |grad alpha|^2 - grad alpha . grad theta * grad rho . grad alpha) * (dpsiN/drho)^2 / B^2
    gds23 = (gradrho_gradthet*gradalph2-gradalph_gradthet*gradrho_gradalph)*(dpsidrho/bmag)**2
    ! (grad rho . grad theta * grad rho . grad alpha - grad alpha . grad theta * |grad rho|^2) * (dpsiN/drho)^2 / B^2 * q/rho
    gds24 = (gradrho_gradthet*gradrho_gradalph-gradalph_gradthet*grho**2)*(dpsidrho/bmag)**2*(local%qinp/local%rhoc)

    ! note that kperp2 = (n0/a)^2*(drho/dpsiN)^2*(gds2 + 2*theta0*gds21 + theta0^2*gds22)

  end subroutine get_gds

  subroutine get_dBdrho (bmag, dIdrho)

    implicit none

    real, dimension (-nz:), intent (in) :: bmag
    real, intent (in) :: dIdrho

    ! dB/drho
    dBdrho = ( bi*dIdrho + 0.5*dgpsi2dr ) / (bmag*Rr(2,:)**2) &
         - bmag*dRdrho/Rr(2,:)

  end subroutine get_dBdrho

  subroutine get_varthet (dpsidrho)

    implicit none

    real, intent (in) :: dpsidrho

    call theta_integrate_indef(jacrho/Rr(2,:)**2, varthet)
    varthet = bi*varthet/(dpsidrho*local%qinp)

  end subroutine get_varthet

  subroutine get_dvarthdr (dpsidrho, dIdrho)

    implicit none

    real, intent (in) :: dpsidrho, dIdrho

    real, dimension (-nz:nz) :: dum

    dum = bi*jacrho*( dIdrho/bi - dqdr/local%qinp + djacdrho/jacrho &
         - 2.*dRdrho/Rr(2,:) )/Rr(2,:)**2
    call theta_integrate_indef(dum, dvarthdr)
    dvarthdr = dvarthdr/(dpsidrho*local%qinp)

  end subroutine get_dvarthdr

  subroutine get_d2Idr2_d2jacdr2 (grho, dIdrho)

    use constants, only: pi

    implicit none

    real, dimension (-nz:), intent (in) :: grho
    real, intent (in) :: dIdrho

    real :: denom, num1, num2, num3, num4
    real, dimension (-nz:nz) :: tmp, tmp2

    ! denom is the denominator in the expression for d^2 I / dr^2
    tmp = jacrho/Rr(2,:)**2*(1.0 + (bi/gpsi)**2)
    call theta_integrate (tmp(-nz2pi:nz2pi), denom)
    denom = denom/bi

    d2jacdr2 = dIdrho*bi*jacrho/gpsi**2 &
         * (dIdrho/bi + djacrdrho/jacrho - dgpsi2dr/gpsi**2 &
         - 2.*dRdrho/Rr(2,:))
    
    tmp = -d2jacdr2/Rr(2,:)**2 - dIdrho*jacrho/(bi*Rr(2,:)**2) &
         * (djacrdrho/jacrho - dIdrho/bi - 2.*dRdrho/Rr(2,:))
    call theta_integrate (tmp(-nz2pi:nz2pi), num1)

    ! tmp = -jacrho/(dpsidrho*Rr(2,:)**2)*(djacdrho/jacrho - 2.*dRdrho/Rr(2,:))
    ! call theta_integrate (tmp(-nz2pi:nz2pi), num2)
    ! d2jacdr2 = d2jacdr2 - tmp*Rr(2,:)**2*local%d2psidr2
    ! num2 = local%d2psidr2 * (2*pi*local%qinp/bi*(dqdr/local%qinp - dIdrho/bi) + num2)
    
    tmp = (d2Rdr2*dRdth+dRdrho*d2Rdrdth+d2Zdr2*dZdth+dZdrho*d2Zdrdth)/jacrho &
         - djacrdrho*(dRdrho*dRdth+dZdrho*dZdth)/jacrho**2
    call get_dthet (tmp, tmp2)
    tmp = (tmp2 - 2./jacrho*(-djacrdrho/jacrho*(dRdth*d2Rdrdth+dZdth*d2Zdrdth) &
         + d2Rdrdth**2 + dRdth*d2Rdr2dth + d2Zdrdth**2 + dZdth*d2Zdr2dth))/grho**2 &
         - dgr2dr*(drzdth - 2./jacrho*(dRdth*d2Rdrdth + dZdth*d2Zdrdth))/grho**4
    call theta_integrate (tmp(-nz2pi:nz2pi), num2)
    d2jacdr2 = d2jacdr2 - tmp*Rr(2,:)**2

    tmp = jacrho*(local%betadbprim + local%betaprim*(djacrdrho/jacrho- dgpsi2dr/gpsi**2))/gpsi**2
    call theta_integrate (tmp(-nz2pi:nz2pi), num3)
    d2jacdr2 = d2jacdr2 - tmp*Rr(2,:)**2

    tmp = jacrho/Rr(2,:)**2*(2.*d2Rdr2/Rr(2,:) - 2.*(dRdrho/Rr(2,:))**2 &
         + local%d2qdr2/local%qinp - (dqdr/local%qinp)**2 + (2*dRdrho/Rr(2,:) + dqdr/local%qinp) &
         * (djacrdrho/jacrho - 2.*dRdrho/Rr(2,:)))
    call theta_integrate (tmp(-nz2pi:nz2pi), num4)

    d2Idr2 = (num1+num2+num3+num4)/denom
!    d2jacdr2 = d2jacdr2 + bi*jacrho/(gpsi*Rr(2,:))**2*d2Idr2 + 2.*djacdrho*dRdrho/Rr(2,:)**3
    d2jacdr2 = d2jacdr2 + bi*jacrho/gpsi**2*d2Idr2 + 2.*djacdrho*dRdrho/Rr(2,:)

  end subroutine get_d2Idr2_d2jacdr2

  subroutine get_d2varthdr2 (dpsidrho, dIdrho)

    implicit none

    real, intent (in) :: dpsidrho, dIdrho

    real, dimension (-nz:nz) :: dum

    dum = bi*jacrho/(local%qinp*dpsidrho*Rr(2,:)**2)*( (dIdrho/bi - dqdr/local%qinp &
!    dum = bi*jacrho/(local%qinp*Rr(2,:)**2)*( (dIdrho/bi - dqdr/local%qinp &
         + djacdrho/jacrho - 2.*dRdrho/Rr(2,:))**2 &
         + d2Idr2/bi - (dIdrho/bi)**2 - local%d2qdr2/local%qinp &
         + (dqdr/local%qinp)**2 + d2jacdr2/jacrho - (djacdrho/jacrho)**2 &
         - djacdrho*local%d2psidr2/(dpsidrho*jacrho) &
         - 2.*d2Rdr2/Rr(2,:) + 2.*(dRdrho/Rr(2,:))**2 )
    call theta_integrate_indef(dum, d2varthdr2)

  end subroutine get_d2varthdr2

  subroutine get_d2Bdr2 (bmag, dIdrho)

    implicit none

    real, dimension (-nz:), intent (in) :: bmag
    real, intent (in) :: dIdrho

    ! d2gpsidr2 = 2.*( dgr2dr*(dRdrho/Rr(2,:) - djacdrho/jacrho) &
    !      + grho**2*(d2Rdr2/Rr(2,:) - (dRdrho/Rr(2,:))**2 - d2jacdr2/jacrho &
    !      + djacdrho*djacrdrho/jacrho**2) + (Rr(2,:)/jacrho)**2 &
    !      * (dRdth**2 + dRdth*d2Rdr2dth + dZdth**2 + dZdth*d2Zdr2dth &
    !      + 2.*(dRdrho/Rr(2,:) - djacrdrho/jacrho)*(dRdth*d2Rdrdth+dZdth*d2Zdrdth)) )
    d2gpsidr2 = 2.*(dRdrho/Rr(2,:)-djacdrho/jacrho)*dgpsi2dr &
         + 2.*gpsi**2*(d2Rdr2/Rr(2,:)-(dRdrho/Rr(2,:))**2 - d2jacdr2/jacrho + djacdrho*djacrdrho/jacrho**2) &
         + 2.*(Rr(2,:)*gpsi/jacrho)**2*( d2Rdrdth**2 + dRdth*d2Rdr2dth + d2Zdrdth**2 + dZdth*d2Zdr2dth &
         + 2.*(dRdth*d2Rdrdth + dZdth*d2Zdrdth)*(dRdrho/Rr(2,:)-djacdrho/jacrho) )

    ! d2gpsidr2 = 2.*(dpsidrho*Rr(2,:)/jacrho)**2 &
    !      * (2.*(dRdrho/Rr(2,:)-djacdrho/jacrho) &
    !      * ((dRdrho/Rr(2,:)-djacdrho/jacrho)*(dRdth**2+dZdth**2) &
    !      + 2.*(dRdth*d2Rdrdth+dZdth*d2Zdrdth)) &
    !      + (dRdth**2+dZdth**2)*(d2rdr2/Rr(2,:) - (dRdrho/Rr(2,:))**2 &
    !      - d2jacdr2/jacrho + (djacdrho/jacrho)**2) &
    !      + d2Rdrdth**2 + dRdth*d2Rdr2dth + d2Zdrdth**2 + dZdth*d2Zdr2dth) &
    !      + 4.*dpsidrho*local%d2psidr2*dgr2dr &
    !      + 2.*grho**2*(local%d2psidr2**2 + dpsidrho*local%d3psidr3)

    ! get d/drho (dB/drho)
    d2Bdr2 = -dBdrho*dRdrho/Rr(2,:) + bmag*(dRdrho/Rr(2,:))**2 &
         - bmag*d2Rdr2/Rr(2,:) + 0.5*(2.*(dIdrho**2 + bi*d2Idr2) &
         + d2gpsidr2)/(bmag*Rr(2,:)**2) &
         - (dBdrho + bmag*dRdrho/Rr(2,:))*(2.*dRdrho/Rr(2,:)+dBdrho/bmag)

  end subroutine get_d2Bdr2

  subroutine get_dcrossdr (dpsidrho, dIdrho, grho)

    implicit none

    real, intent (in) :: dpsidrho, dIdrho
    real, dimension (-nz:), intent (in) :: grho

    ! dgr2 = d/drho (|grad rho|^2)
    ! dgr2 = 2.*(Rr(2,:)/jacrho)**2*((dRdrho/Rr(2,:)-djacdrho/jacrho)*(dRdth**2+dZdth**2) &
    !      + dRdth*d2Rdrdth + dZdth*d2Zdrdth)
    ! dgrgt = d/drho (grad rho . grad theta)
!    dgrgt = -(Rr(2,:)/jacrho)**2*(2.*(dRdrho/Rr(2,:)-djacdrho/jacrho)*(dRdrho*dRdth+dZdrho*dZdth) &
!         + d2Rdr2*dRdth+dRdrho*d2Rdrdth+d2Zdr2*dZdth+dZdrho*d2Zdrdth)
    dgrgt = 2.*gradrho_gradthet*(dRdrho/Rr(2,:)-djacrdrho/jacrho) &
         - (Rr(2,:)/jacrho)**2*(d2Rdr2*dRdth + dRdrho*d2Rdrdth + d2Zdr2*dZdth + dZdrho*d2Zdrdth)
    ! dgt2 = d/drho (|grad theta|^2)
    dgt2 = 2.*(Rr(2,:)/jacrho)**2*((dRdrho/Rr(2,:)-djacrdrho/jacrho)*(dRdrho**2+dZdrho**2) &
         + dRdrho*d2Rdr2 + dZdrho*d2Zdr2)
    ! this is d/drho (|grad alph|^2)
    ! will later multiply it by 0.5*dpsidrho**2
    dga2 = -2*dRdrho/Rr(2,:)**3 + dgr2dr*(varthet*dqdr+local%qinp*dvarthdr)**2 &
         + (2.0*grho**2*(varthet*dqdr+local%qinp*dvarthdr) &
         + 2.*bi*jacrho*gradrho_gradthet/(dpsidrho*Rr(2,:)**2)) &
         * (local%d2qdr2*varthet+2.*dqdr*dvarthdr+local%qinp*d2varthdr2) &
         + 2.*(varthet*dqdr+local%qinp*dvarthdr)*bi*jacrho/(dpsidrho*Rr(2,:)**2) &
         * (dgrgt + gradrho_gradthet*(dIdrho/bi + djacdrho/jacrho - 2.*dRdrho/Rr(2,:))) &
         + (bi*jacrho/(dpsidrho*Rr(2,:)**2))**2*(dgt2 + 2.*gradthet2*(dIdrho/bi + djacdrho/jacrho &
         - 2.*dRdrho/Rr(2,:)))

    ! dgagr = d/drho (grad alpha . grad rho)
    dgagr = -grho**2*(2.*dvarthdr*dqdr+varthet*local%d2qdr2+local%qinp*d2varthdr2) &
         - dgr2dr*(varthet*dqdr+local%qinp*dvarthdr) - bi*jacrho/(dpsidrho*Rr(2,:)**2) &
         * (dgrgt + gradrho_gradthet*(dIdrho/bi + djacdrho/jacrho - 2.*dRdrho/Rr(2,:)))

    ! dgagt = d/drho (grad alpha . grad theta)
    dgagt = -gradrho_gradthet*(2.*dvarthdr*dqdr+varthet*local%d2qdr2+local%qinp*d2varthdr2) &
         - dgrgt*(varthet*dqdr+local%qinp*dvarthdr) - bi*jacrho/(dpsidrho*Rr(2,:)**2) &
         * (dgt2 + gradthet2*(dIdrho/bi + djacdrho/jacrho - 2.*dRdrho/Rr(2,:)))

    ! dcrossdr = d/drho [(grad alpha x B) . grad theta)]
    dcrossdr = dpsidrho*(dgagr*gradalph_gradthet+gradrho_gradalph*dgagt &
         - dga2*gradrho_gradthet - gradalph2*dgrgt) + local%d2psidr2*cross/dpsidrho

    ! this is (dpsi/drho)^2*d|grad alpha|^2/dr
    dgds2dr = dga2*dpsidrho**2
    ! this is (dpsi/drho)^2*d(grad alpha . grad q)/dr
    ! note that there will be multiplication by 2 in dist_fn.fpp
    dgds21dr = (dgagr*dqdr+local%d2qdr2*gradrho_gradalph)*dpsidrho**2
    ! this is (dpsi/drho)^2*d(|grad q|^2)/dr
    dgds22dr = (dqdr**2*dgr2dr + 2.*grho**2*dqdr*local%d2qdr2)*dpsidrho**2

    ! note that dkperp2/dr = (n0/a)^2*(drho/dpsiN)^2*(dgds2dr + 2*theta0*dgds21dr + theta0^2*dgds22dr)

  end subroutine get_dcrossdr

  subroutine theta_integrate (integrand, integral)

    implicit none

    real, dimension (-nz2pi:), intent (in) :: integrand
    real, intent (out) :: integral

    ! use trapezoidal rule to integrate in theta
    integral = 0.5*sum(delthet(-nz2pi:nz2pi-1)*(integrand(-nz2pi:nz2pi-1) + integrand(-nz2pi+1:nz2pi)))

  end subroutine theta_integrate

  ! get indefinite integral of integrand
  subroutine theta_integrate_indef (integrand, integral)

    implicit none

    real, dimension (-nz:), intent (in) :: integrand
    real, dimension (-nz:), intent (out) :: integral

    integer :: i

    ! use trapezoidal rule to integrate in theta
    integral(0) = 0.0
    do i = 1, nz
       integral(i) = integral(i-1)+0.5*delthet(i-1)*(integrand(i-1)+integrand(i))
    end do
    do i = -1, -nz, -1
       integral(i) = integral(i+1)-0.5*delthet(i)*(integrand(i+1)+integrand(i))
    end do

  end subroutine theta_integrate_indef

!   subroutine leqcoefs (dgpdr, dgpbdr, dcvd0dr, dgbd0dr, dcvdr, dgbdr, dg2dr, dg21dr, dg22dr, dbdr, &
!        gs2, gs21, gs22, gpar, gbd0, cvd0, gbd, cvd, drdpsi, gr, b, bpol, dkxfacdr)

!     implicit none

!     real, dimension (-nz:), intent (out) :: dgpdr, dgpbdr, dcvd0dr, dgbd0dr, dcvdr, dgbdr
!     real, dimension (-nz:), intent (out) :: dg2dr, dg21dr, dg22dr, dbdr
!     real, dimension (-nz:), intent (out) :: gs2, gs21, gs22, gpar, gbd0, cvd0, gbd, cvd
!     real, dimension (-nz:), intent (out) :: gr, b, bpol
!     real, intent (out) :: drdpsi, dkxfacdr

!     integer :: i

!     drdpsi = 1./dpsidrho
!     gr = grho
!     b = bmag
!     bpol = gpsi/Rr(2,:)
!     gs2 = gds2
!     gs21 = gds21
!     gs22 = gds22
!     gpar = gradpar
!     gbd0 = gbdrift0
!     cvd0 = cvdrift0
!     gbd = gbdrift
!     cvd = cvdrift
!     dgpdr = dgradpardrho
!     dgpbdr = dgradparbdrho
!     dcvd0dr = dcvdrift0drho
!     dgbd0dr = dgbdrift0drho
!     dcvdr = dcvdriftdrho
!     dgbdr = dgbdriftdrho
!     dg2dr = dgds2dr
!     dg21dr = dgds21dr
!     dg22dr = dgds22dr
!     dbdr = dBdrho
!     ! factor multiplying kx in dkx/dr
!     if (dqdr > epsilon(0.)) then 
!        dkxfacdr = local%d2qdr2/dqdr - local%d2psidr2/dpsidrho
!     else
!        write (*,*) 'WARNING (if running with profile_variation=T): dq/dr=0 case currently excludes nonlinear piece in dg/dr equation'
!        dkxfacdr = 0.
!     end if

!   end subroutine leqcoefs

  function Rpos (r, theta, j)
   
    use constants, only: pi

    integer, intent (in) :: j
    real, intent (in) :: r, theta
    real :: Rpos
    real :: g, gp, dr
    integer :: i
    
    dr = r - local%rhoc

! For Y Xiao: 
!    g = local%delp/local%rhoc + local%d * sin(theta)**2
!    Rpos = local%rmaj*(1.+r*(cos(theta)-g)-g*dr)

    g = cos(theta + local%tri * sin(theta))
    gp = -sin(theta + local%tri * sin(theta)) &
         *local%triprim*sin(theta)

    ! allow for strange specification of R_psi
    if (j==nz+1) then
       i = -nz
    else
       i = j
    end if
    
    ! second line here is (1/2)*(r-r0)**2*d2R/dr|_r0
    ! note that d2R=0 unless read_profile_variation = T in input file
    Rpos = local%rmaj + local%shift*dr + g*local%rhoc + (g+local%rhoc*gp)*dr &
         + 0.5*(r-0.5)**2*d2R(i)
    
  end function Rpos

  function Zpos (r, theta, j)
   
    integer, intent (in) :: j
    real, intent (in) :: r, theta
    real :: Zpos, dr
    integer :: i

    ! allow for strange specification of Z_psi
    if (j==nz+1) then
       i = -nz
    else
       i = j
    end if

    dr = r - local%rhoc
    ! note that d2Z=0 unless read_profile_variation=T in input file
    Zpos = local%kappa*sin(theta)*local%rhoc + (local%rhoc*local%kapprim + local%kappa)*sin(theta)*dr &
         + 0.5*(r-0.5)**2*d2Z(i)
    
  end function Zpos

  function mod2pi (theta)
    
    real, intent(in) :: theta
    real :: pi, th, mod2pi
    real, parameter :: theta_tol = 1.e-6
    logical :: out
    
    pi=2.*acos(0.)
    
    if(theta <= pi .and. theta >= -pi) then
       mod2pi = theta
       return
    endif
    
    if(theta - theta_tol <= pi .and. theta >= -pi) then
       mod2pi = pi
       return
    endif

    if(theta <= pi .and. theta + theta_tol >= -pi) then
       mod2pi = -pi
       return
    endif

    th=theta
    out=.true.
    do while(out)
       if(th > pi) th = th - 2.*pi
       if(th <-pi) th = th + 2.*pi
       if(th <= pi .and. th >= -pi) out=.false.
    enddo
    mod2pi=th
    
  end function mod2pi
   
end module millerlocal
