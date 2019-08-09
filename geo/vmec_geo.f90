module vmec_geo

  implicit none

  public :: read_vmec_parameters
  public :: get_vmec_geo

  integer :: nalpha
  real :: alpha0
  integer :: zgrid_refinement_factor
  real :: zgrid_scalefac
  integer :: surface_option
  real :: nfield_periods
  real :: zeta_center, torflux
  logical :: verbose
  character (2000) :: vmec_filename
  
contains

  subroutine read_vmec_parameters (nalpha_out)

    use file_utils, only: input_unit_exist
    use mp, only: mp_abort
    use zgrid, only: zed_equal_arc

    implicit none

    integer, intent (out) :: nalpha_out

    integer :: in_file
    logical :: exist

    namelist /vmec_parameters/ nalpha, alpha0, zeta_center, nfield_periods, &
         torflux, zgrid_scalefac, zgrid_refinement_factor, surface_option, verbose, vmec_filename

    call init_vmec_defaults

    in_file = input_unit_exist("vmec_parameters", exist)
    if (exist) read (unit=in_file, nml=vmec_parameters)

    if (zgrid_scalefac < 1.0-epsilon(0.)) then
       write (*,*) 'zgrid_scalefac = ', zgrid_scalefac
       call mp_abort ('zgrid_scalefac should always be >= 1.0.  aborting')
    else if (.not.zed_equal_arc) then
       if (zgrid_scalefac > 1.0+epsilon(0.)) then
          write (*,*) 'There is no reason to use zgrid_scalefac different from 1.0 unless zed_equal_arc=T'
          write (*,*) 'Setting zgrid_scalefac = 1.0'
          zgrid_scalefac = 1.0
       else if (zgrid_refinement_factor > 1) then
          write (*,*) 'There is no reason to use zgrid_refinement_factor > 1 unless zed_equal_arc=T'
          write (*,*) 'Setting zgrid_refinement_factor = 1'
          zgrid_refinement_factor = 1
       end if
    end if

    nalpha_out = nalpha

  end subroutine read_vmec_parameters

  subroutine init_vmec_defaults

    use zgrid, only: zed_equal_arc

    implicit none

    vmec_filename = 'equilibria/wout_w7x_standardConfig.nc'
    nalpha = 1
    alpha0 = 0.0
    zeta_center = 0.0
    nfield_periods = -1.0
    torflux = 0.6354167d+0
    surface_option = 0
    verbose = .true.
    ! if simulating entire flux surface,
    ! must obtain vmec geo quantities
    ! on zeta grid that is longer than
    ! will ultimately be used in simulation
    ! this is related to need for gradpar to
    ! be independent of alpha
    if (zed_equal_arc) then
       zgrid_scalefac = 2.0
       zgrid_refinement_factor = 4
    else
       zgrid_scalefac = 1.0
       zgrid_refinement_factor = 1
    end if

  end subroutine init_vmec_defaults

  subroutine get_vmec_geo (nzgrid, surf, grho, bmag, gradpar, gds2, gds21, gds22, &
       gds23, gds24, gds25, gds26, gbdrift, gbdrift0, cvdrift, cvdrift0, sign_torflux, &
       theta_vmec, zed_scalefac, L_reference, B_reference, alpha)

    use constants, only: pi
    use common_types, only: flux_surface_type
    use splines, only: geo_spline
    use vmec_to_stella_geometry_interface_mod, only: vmec_to_stella_geometry_interface
    use vmec_to_stella_geometry_interface_mod, only: read_vmec_equilibrium
    use zgrid, only: zed_equal_arc, get_total_arc_length, get_arc_length_grid
    use zgrid, only: zed

    implicit none

    integer, intent (in) :: nzgrid
    type (flux_surface_type), intent (out) :: surf
    real, dimension (:,-nzgrid:), intent (out) :: grho, bmag, gradpar, gds2, gds21, gds22, &
         gds23, gds24, gds25, gds26, gbdrift, gbdrift0, cvdrift, cvdrift0, theta_vmec
    real, dimension (:), intent (out) :: alpha
    real, intent (out) :: zed_scalefac, L_reference, B_reference
    integer, intent (out) :: sign_torflux

    integer :: i, j, ia
    integer :: nzgrid_vmec
    integer :: zetamax_idx
    real :: nfp

    real, dimension (:), allocatable :: zeta_vmec
    real, dimension (:,:), allocatable :: bmag_vmec, gradpar_vmec
    real, dimension (:,:), allocatable :: gds2_vmec, gds21_vmec, gds22_vmec
    real, dimension (:,:), allocatable :: gds23_vmec, gds24_vmec, gds25_vmec, gds26_vmec
    real, dimension (:,:), allocatable :: gbdrift_vmec, gbdrift0_vmec
    real, dimension (:,:), allocatable :: cvdrift_vmec, cvdrift0_vmec

    real, dimension (:), allocatable :: zed_domain_size
    real, dimension (:,:), allocatable :: arc_length

!    real, dimension (nalpha) :: alpha
    real :: dzeta_vmec, zmin, zmax
    real, dimension (nalpha,-nzgrid:nzgrid) :: zeta
    real, dimension (nalpha,-nzgrid:nzgrid) :: theta

    ! first read in equilibrium information from vmec file
    ! this is stored as a set of global variables in read_wout_mod
    ! in mini_libstell.  it will be accessible
    call read_vmec_equilibrium (vmec_filename)

    ! nzgrid_vmec is the number of positive/negative zeta locations
    ! at which to get geometry data from vmec
    ! can be > than nzgrid for full_flux_surface case
    ! where z(zeta_max)-z(zeta_min) varies with alpha
    ! and thus a larger than usual range of zeta_max/min
    ! values are needed to avoid extrapolation
    if (zed_equal_arc) then
       call get_modified_vmec_zeta_grid (nzgrid_vmec, dzeta_vmec)
    else
       nzgrid_vmec = nzgrid
    end if

    ! allocate arrays of size 2*nzgrid_vmec+1
    allocate (zeta_vmec(-nzgrid_vmec:nzgrid_vmec))
    allocate (bmag_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (gradpar_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (gds2_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (gds21_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (gds22_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (gds23_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (gds24_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (gds25_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (gds26_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (gbdrift_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (gbdrift0_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (cvdrift_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (cvdrift0_vmec(nalpha,-nzgrid_vmec:nzgrid_vmec))
    allocate (arc_length(nalpha,-nzgrid_vmec:nzgrid_vmec))

    call vmec_to_stella_geometry_interface (nalpha, alpha0, &
         nzgrid_vmec, zeta_center, nfield_periods*zgrid_scalefac, torflux, &
         surface_option, verbose, &
         surf%rhoc, surf%qinp, surf%shat, L_reference, B_reference, nfp, &
         sign_torflux, alpha, zeta_vmec, &
         bmag_vmec, gradpar_vmec, gds2_vmec, gds21_vmec, &
         gds22_vmec, gds23_vmec, gds24_vmec, &
         gds25_vmec, gds26_vmec, gbdrift_vmec, gbdrift0_vmec, cvdrift_vmec, &
         cvdrift0_vmec, theta_vmec)

    allocate (zed_domain_size(nalpha))

    if (nzgrid_vmec /= nzgrid) then
       ! must interpolate geometric quantities from (zeta,alpha) grid to
       ! (zed,alpha) grid, with zed the arc-length

       ! first need to get zed(zeta,alpha)
       ! defined via 1 = b . grad z = b . grad zeta * dz/dzeta
       ! note that nzgrid*zgrid_refinement_factor gives index
       ! for the max zeta of the nominal zeta grid
       zetamax_idx = nzgrid*zgrid_refinement_factor
       do ia = 1, nalpha
          ! this is z(zeta_max) - z(zeta_min) for nominal zeta domain
          call get_total_arc_length (zetamax_idx, gradpar_vmec(ia,-zetamax_idx:zetamax_idx), &
               dzeta_vmec, zed_domain_size(ia))
          ! now get z(zeta) = 
          zmin = -zed_domain_size(ia)*0.5
          call get_arc_length_grid (zetamax_idx, nzgrid_vmec, zmin, &
               gradpar_vmec(ia,:), dzeta_vmec, arc_length(ia,:))
       end do

       ! now that we know the min/max values of z corresponding to min/max values
       ! of the nominal zeta at each of the alphas, construct a regular z grid
       ! make the max z value on this regular grid to the the maximum over all alpha
       ! of z(zeta_max,alpha)
       zmax = maxval(zed_domain_size)*0.5

       ! scale zed so that it is arc-length compressed (or expanded)
       ! to the range [-pi:pi]
       zed_scalefac = pi/zmax
       arc_length = arc_length*zed_scalefac

       do ia = 1, nalpha
          ! now that we have z(alpha,zeta), interpolate from regular zeta grid (which is irregular in z)
          ! to regular zed grid (irregular in zeta)
          call geo_spline (arc_length(ia,:), zeta_vmec, zed, zeta(ia,:))
          call geo_spline (arc_length(ia,:), gradpar_vmec(ia,:), zed, gradpar(ia,:))
          call geo_spline (arc_length(ia,:), bmag_vmec(ia,:), zed, bmag(ia,:))
          call geo_spline (arc_length(ia,:), gds2_vmec(ia,:), zed, gds2(ia,:))
          call geo_spline (arc_length(ia,:), gds21_vmec(ia,:), zed, gds21(ia,:))
          call geo_spline (arc_length(ia,:), gds22_vmec(ia,:), zed, gds22(ia,:))
          call geo_spline (arc_length(ia,:), gds23_vmec(ia,:), zed, gds23(ia,:))
          call geo_spline (arc_length(ia,:), gds24_vmec(ia,:), zed, gds24(ia,:))
          call geo_spline (arc_length(ia,:), gds25_vmec(ia,:), zed, gds25(ia,:))
          call geo_spline (arc_length(ia,:), gds26_vmec(ia,:), zed, gds26(ia,:))
          call geo_spline (arc_length(ia,:), gbdrift_vmec(ia,:), zed, gbdrift(ia,:))
          call geo_spline (arc_length(ia,:), gbdrift0_vmec(ia,:), zed, gbdrift0(ia,:))
          call geo_spline (arc_length(ia,:), cvdrift_vmec(ia,:), zed, cvdrift(ia,:))
          call geo_spline (arc_length(ia,:), cvdrift0_vmec(ia,:), zed, cvdrift0(ia,:))

          ! gradpar at this point is b . grad zeta
          ! but want it to be b . grad z = b . grad zeta * dz/dzeta
          ! we have constructed z so that b . grad z = 1
          ! so dz/dzeta = 1 / b . grad zeta
          ! gds23 and gds24 involve grad z factors
          ! but currently calculated in terms of grad zeta
          ! so convert via multiplication with dz/dzeta
          gds23(ia,:) = gds23(ia,:)/gradpar(ia,:)
          gds24(ia,:) = gds24(ia,:)/gradpar(ia,:)
          gradpar(ia,:) = 1.0
       end do
    else
       zeta = spread(zeta_vmec,1,nalpha)
       bmag = bmag_vmec
       gradpar = gradpar_vmec
       gds2 = gds2_vmec
       gds21 = gds21_vmec
       gds22 = gds22_vmec
       gds23 = gds23_vmec
       gds24 = gds24_vmec
       gds25 = gds25_vmec
       gds26 = gds26_vmec
       gbdrift = gbdrift_vmec
       gbdrift0 = gbdrift0_vmec
       cvdrift = cvdrift_vmec
       cvdrift0 = cvdrift0_vmec

       ! scale zed so that it is zeta compressed (or expanded)
       ! to the range [-pi,pi]
       ! this is 1/p from stella JCP paper
       zed_scalefac = real(nfp)/nfield_periods
    end if

    ! this is b . grad zed
    ! with zed = zeta or arc-length scaled to run from -pi to pi
    gradpar = gradpar*zed_scalefac
    gds23 = gds23*zed_scalefac
    gds24 = gds24*zed_scalefac
    
    ! arrays over extended zeta-grid no longer needed, so deallocate
    deallocate (zed_domain_size)
    deallocate (zeta_vmec)
    deallocate (bmag_vmec, gradpar_vmec)
    deallocate (gds2_vmec, gds21_vmec, gds22_vmec)
    deallocate (gds23_vmec, gds24_vmec, gds25_vmec, gds26_vmec)
    deallocate (gbdrift_vmec, gbdrift0_vmec)
    deallocate (cvdrift_vmec, cvdrift0_vmec)
    deallocate (arc_length)
    
    ! vmec_to_stella_geometry_interface returns psitor/psitor_lcfs as rhoc
    ! stella uses rhoc = sqrt(psitor/psitor_lcfs) = rhotor
    surf%rhoc = sqrt(surf%rhoc)
    surf%rhotor = surf%rhoc
    ! grho = |grad rho| = |drho/dx| * |grad x|
    ! |drho/dx| = L_reference
    ! gds22 = shat^2 * |grad x|^2
    grho = sqrt(gds22/surf%shat**2)/L_reference
    surf%drhotordrho = 1.0
    surf%psitor_lcfs = 0.5*sign_torflux

    ! scale the vmec output
    ! alpha = theta_pest - iota*zeta
    ! theta_pest = theta_vmec + Lambda(psi,alpha,theta_vmec)
    ! with theta_pest a straight-field-line angle
    ! but not theta_vmec
    ! so theta is theta_pest up to constant (alpha)

!    theta = zeta/nfp/surf%qinp
    theta = spread(alpha,2,2*nzgrid+1)+zeta/surf%qinp
    ! this is the vmec theta (not straight-field-line coordinate)
    ! scaled to run between -pi and pi
    theta_vmec = theta_vmec/nfp

    open (2001,file='vmec.geo',status='unknown')
    write (2001,'(6a12)') 'rhotor', 'qinp', 'shat', 'aref', 'Bref', 'z_scalefac'
    write (2001,'(6e12.4)') surf%rhoc, surf%qinp, surf%shat, L_reference, B_reference, zed_scalefac
    write (2001,*)
    write (2001,'(14a12)') '#    alpha', 'zeta', 'bmag', 'gradpar', 'gds2',&
         'gds21', 'gds22', 'gds23', 'gds24','gbdrift', 'gbdrift0', 'cvdrift',&
         'cvdrift0', 'theta_vmec'
    do j = -nzgrid, nzgrid
       do i = 1, nalpha
          write (2001,'(14e12.4)') alpha(i), zeta(i,j), bmag(i,j), gradpar(i,j), &
               gds2(i,j), gds21(i,j), gds22(i,j), gds23(i,j), gds24(i,j), &
               gbdrift(i,j), gbdrift0(i,j), cvdrift(i,j), cvdrift0(i,j), theta_vmec(i,j)
       end do
    end do
    close (2001)

  end subroutine get_vmec_geo

  subroutine get_modified_vmec_zeta_grid (nzgrid_modified, dzeta_modified)

    use zgrid, only: nzgrid
    use vmec_to_stella_geometry_interface_mod, only: get_nominal_vmec_zeta_grid

    implicit none

    integer, intent (out) :: nzgrid_modified

    integer :: nzgrid_excess
    real :: nfield_periods_device
    real :: zeta_max, excess_zeta
    real :: tmp, dzeta, dzeta_modified
    real, dimension (:), allocatable :: zeta

    ! need to extend the maximum and minimum zeta values
    ! by zgrid_scalefac to ensure that we have information
    ! about geometric coefficients everywhere on a fixed
    ! equal-arc grid in zed

    ! first figure out how many extra zeta grid points are
    ! required at the nominal grid spacing to get out
    ! to the ends of the extended zeta domain

    ! first calculate the nominal zeta grid used for vmec
    if (.not.allocated(zeta)) allocate (zeta(-nzgrid:nzgrid))
    ! note that nfield_periods is the number of field periods
    ! sampled in stella, while nfield_periods_device
    ! is the number of field periods in the device
    ! nfield_periods may be reasonably bigger than nfield_periods_device
    ! as the former is sampled while keeping alpha fixed (rather than theta)
    call get_nominal_vmec_zeta_grid (nzgrid, zeta_center, nfield_periods, &
         nfield_periods_device, zeta)

    ! maximum zeta value for nominal zeta grid
    zeta_max = zeta(nzgrid)
    ! excess_zeta is difference between expanded zeta_max and nominal zeta_max
    excess_zeta = zeta_max*(zgrid_scalefac-1.0)
    ! assumes equal grid spacing in zeta
    dzeta = zeta(1)-zeta(0)
    tmp = excess_zeta/dzeta
    ! nzgrid_excess is the number of additional zeta grid points needed to 
    ! cover at least excess_zeta
    if (abs(tmp - nint(tmp)) < 0.1) then
       nzgrid_excess = nint(tmp)
    else
       nzgrid_excess = nint(tmp) + 1
    end if

    ! now refine the zeta grid by desired amount in
    ! preparation for interpolation
    nzgrid_modified = (nzgrid + nzgrid_excess)*zgrid_refinement_factor
    dzeta_modified = dzeta/real(zgrid_refinement_factor)

    if (allocated(zeta)) deallocate (zeta)

  end subroutine get_modified_vmec_zeta_grid

end module vmec_geo
