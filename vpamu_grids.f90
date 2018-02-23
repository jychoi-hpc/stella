module vpamu_grids

  implicit none

  public :: init_vpamu_grids, finish_vpamu_grids
  public :: integrate_vmu, integrate_species
  public :: integrate_mu
  public :: vpa, nvgrid, nvpa
  public :: wgts_vpa, dvpa
  public :: mu, nmu, wgts_mu
  public :: vperp2, maxwell_vpa, maxwell_mu, ztmax
  
  integer :: nvgrid, nvpa
  integer :: nmu
  real :: vpa_max

  ! arrays that are filled in vpamu_grids
  real, dimension (:), allocatable :: mu, wgts_mu
  real, dimension (:), allocatable :: vpa, wgts_vpa
  real, dimension (:), allocatable :: maxwell_vpa
  real, dimension (:,:,:), allocatable :: maxwell_mu
  real, dimension (:,:), allocatable :: ztmax
  real :: dvpa

  ! vpa-mu related arrays that are declared here
  ! but allocated and filled elsewhere because they depend on z, etc.
  real, dimension (:,:,:), allocatable :: vperp2

  interface integrate_species
     module procedure integrate_species_vmu
     module procedure integrate_species_vmu_single
     module procedure integrate_species_local_complex
     module procedure integrate_species_local_real
  end interface

  interface integrate_vmu
     module procedure integrate_vmu_real
     module procedure integrate_vmu_complex
  end interface

  interface integrate_mu
     module procedure integrate_mu_local
     module procedure integrate_mu_nonlocal
  end interface

contains

  subroutine init_vpamu_grids

    implicit none

    logical, save :: initialized = .false.

    if (initialized) return
    initialized = .true.

    call read_parameters

    call init_vpa_grid
    call init_mu_grid

  end subroutine init_vpamu_grids

  subroutine read_parameters

    use file_utils, only: input_unit_exist
    use mp, only: proc0, broadcast

    implicit none

    namelist /vpamu_grids_parameters/ nvgrid, nmu, vpa_max

    integer :: in_file
    logical :: exist

    if (proc0) then

       nvgrid = 24
       vpa_max = 3.0
       nmu = 12

       in_file = input_unit_exist("vpamu_grids_parameters", exist)
       if (exist) read (unit=in_file, nml=vpamu_grids_parameters)

    end if

    call broadcast (nvgrid)
    call broadcast (vpa_max)
    call broadcast (nmu)

    nvpa = 2*nvgrid+1

  end subroutine read_parameters

  subroutine init_vpa_grid

    use species, only: spec, nspec

    implicit none

    integer :: iv, idx, iseg, nvpa_seg
    real :: del

    if (.not. allocated(vpa)) then
       ! vpa is the parallel velocity at grid points
       allocate (vpa(-nvgrid:nvgrid)) ; vpa = 0.0
       ! wgts_vpa are the integration weights assigned
       ! to the parallel velocity grid points
       allocate (wgts_vpa(-nvgrid:nvgrid)) ; wgts_vpa = 0.0
       ! this is the Maxwellian in vpa
       allocate (maxwell_vpa(-nvgrid:nvgrid)) ; maxwell_vpa = 0.0
       allocate (ztmax(-nvgrid:nvgrid,nspec)) ; ztmax = 0.0
    end if

    ! velocity grid goes from -vpa_max to vpa_max
    ! with a point at vpa = 0

    ! obtain vpa grid for vpa >= 0
    do iv = 0, nvgrid
       vpa(iv) = real(iv)*vpa_max/nvgrid
    end do
    ! fill in vpa grid for vpa < 0
    vpa(-nvgrid:-1) = -vpa(nvgrid:1:-1)

    ! equal grid spacing in vpa
    dvpa = vpa(1)-vpa(0)

    ! this is the equilibrium Maxwellian in vpa
    maxwell_vpa = exp(-vpa*vpa)
    ztmax = spread(spec%zt,1,nvpa)*spread(maxwell_vpa,2,nspec)

    ! get integration weights corresponding to vpa grid points
    ! for now use Simpson's rule; 
    ! i.e. subdivide grid into 3-point segments, with each segment spanning vpa_low to vpa_up
    ! then the contribution of each segment to the integral is
    ! (vpa_up - vpa_low) * (f1 + 4*f2 + f3) / 6
    ! inner boundary points are used in two segments, so they get double the weight
    nvpa_seg = (2*nvgrid+1)/2
    do iseg = 1, nvpa_seg
       idx = -nvgrid + (iseg-1)*2
       del = dvpa/3.
       wgts_vpa(idx) = wgts_vpa(idx) + del
       wgts_vpa(idx+1) = wgts_vpa(idx+1) + 4.*del
       wgts_vpa(idx+2) = wgts_vpa(idx+2) + del
    end do

  end subroutine init_vpa_grid

  subroutine integrate_mu_local (iz, g, total)

    use species, only: nspec
    use geometry, only: bmag

    implicit none

    integer, intent (in) :: iz
    real, dimension (:,:), intent (in) :: g
    real, dimension (:), intent (out) :: total

    integer :: is, imu

    total = 0.

    do is = 1, nspec
       ! sum over mu
       do imu = 1, nmu
          total(is) = total(is) + wgts_mu(imu)*bmag(1,iz)*g(imu,is)
       end do
    end do

  end subroutine integrate_mu_local

  subroutine integrate_mu_nonlocal (iz, g, total)

    use mp, only: nproc, sum_reduce
    use stella_layouts, only: vmu_lo
    use stella_layouts, only: is_idx, imu_idx, iv_idx
    use geometry, only: bmag

    implicit none

    integer, intent (in) :: iz
    real, dimension (vmu_lo%llim_proc:), intent (in) :: g
    real, dimension (:,:), intent (out) :: total

    integer :: is, imu, iv, ivmu

    total = 0.
    
    do ivmu = vmu_lo%llim_proc, vmu_lo%ulim_proc
       is = is_idx(vmu_lo,ivmu)
       imu = imu_idx(vmu_lo,ivmu)
       iv = iv_idx(vmu_lo,ivmu) + nvgrid+1
       total(iv,is) = total(iv,is) + wgts_mu(imu)*bmag(1,iz)*g(ivmu)
    end do

    if (nproc > 1) call sum_reduce (total,0)

  end subroutine integrate_mu_nonlocal

  subroutine integrate_vmu_real (g, iz, total)

    use geometry, only: bmag

    implicit none

    real, dimension (-nvgrid:,:), intent (in) :: g
    integer, intent (in) :: iz
    real, intent (out) :: total

    integer :: iv, imu

    total = 0.
    
    do imu = 1, nmu
       do iv = -nvgrid, nvgrid
          total = total + wgts_mu(imu)*wgts_vpa(iv)*bmag(1,iz)*g(iv,imu)
       end do
    end do

  end subroutine integrate_vmu_real

  subroutine integrate_vmu_complex (g, iz, total)

    use geometry, only: bmag

    implicit none

    complex, dimension (-nvgrid:,:), intent (in) :: g
    integer, intent (in) :: iz
    complex, intent (out) :: total

    integer :: iv, imu

    total = 0.
    
    do imu = 1, nmu
       do iv = -nvgrid, nvgrid
          total = total + wgts_mu(imu)*wgts_vpa(iv)*bmag(1,iz)*g(iv,imu)
       end do
    end do

  end subroutine integrate_vmu_complex

  subroutine integrate_species_local_real (g, weights, iz, total)

    use species, only: nspec
    use geometry, only: bmag

    implicit none

    real, dimension (-nvgrid:,:,:), intent (in) :: g
    real, dimension (:), intent (in) :: weights
    integer, intent (in) :: iz
    real, intent (out) :: total

    integer :: iv, imu, is

    total = 0.

    do is = 1, nspec
       do imu = 1, nmu
          do iv = -nvgrid, nvgrid
             total = total + wgts_mu(imu)*wgts_vpa(iv)*bmag(1,iz)*g(iv,imu,is)*weights(is)
          end do
       end do
    end do

  end subroutine integrate_species_local_real

  subroutine integrate_species_local_complex (g, weights, iz, total)

    use species, only: nspec
    use geometry, only: bmag

    implicit none

    complex, dimension (-nvgrid:,:,:), intent (in) :: g
    real, dimension (:), intent (in) :: weights
    integer, intent (in) :: iz
    complex, intent (out) :: total

    integer :: iv, imu, is

    total = 0.

    do is = 1, nspec
       do imu = 1, nmu
          do iv = -nvgrid, nvgrid
             total = total + wgts_mu(imu)*wgts_vpa(iv)*bmag(1,iz)*g(iv,imu,is)*weights(is)
          end do
       end do
    end do

  end subroutine integrate_species_local_complex

  ! integrave over v-space and sum over species
  subroutine integrate_species_vmu (g, weights, total)

    use mp, only: sum_allreduce
    use stella_layouts, only: vmu_lo, iv_idx, imu_idx, is_idx
    use zgrid, only: nzgrid
    use geometry, only: bmag

    implicit none

    integer :: ivmu, iv, iz, is, imu

    complex, dimension (:,:,-nzgrid:,vmu_lo%llim_proc:), intent (in) :: g
    real, dimension (:), intent (in) :: weights
    complex, dimension (:,:,-nzgrid:), intent (out) :: total

    total = 0.

    do ivmu = vmu_lo%llim_proc, vmu_lo%ulim_proc
       iv = iv_idx(vmu_lo,ivmu)
       imu = imu_idx(vmu_lo,ivmu)
       is = is_idx(vmu_lo,ivmu)
       do iz = -nzgrid, nzgrid
          total(:,:,iz) = total(:,:,iz) + &
               wgts_mu(imu)*wgts_vpa(iv)*bmag(1,iz)*g(:,:,iz,ivmu)*weights(is)
       end do
    end do

    call sum_allreduce (total)

  end subroutine integrate_species_vmu

  ! integrave over v-space and sum over species for given (ky,kx,z) point
  subroutine integrate_species_vmu_single (g, iz, weights, total)

    use mp, only: sum_allreduce
    use stella_layouts, only: vmu_lo, iv_idx, imu_idx, is_idx
    use geometry, only: bmag

    implicit none

    integer :: ivmu, iv, is, imu

    complex, dimension (vmu_lo%llim_proc:), intent (in) :: g
    integer, intent (in) :: iz
    real, dimension (:), intent (in) :: weights
    complex, intent (out) :: total

    total = 0.

    do ivmu = vmu_lo%llim_proc, vmu_lo%ulim_proc
       iv = iv_idx(vmu_lo,ivmu)
       imu = imu_idx(vmu_lo,ivmu)
       is = is_idx(vmu_lo,ivmu)
       total = total + &
            wgts_mu(imu)*wgts_vpa(iv)*bmag(1,iz)*g(ivmu)*weights(is)
    end do

    call sum_allreduce (total)

  end subroutine integrate_species_vmu_single

  subroutine finish_vpa_grid

    implicit none

    if (allocated(vpa)) deallocate (vpa)
    if (allocated(wgts_vpa)) deallocate (wgts_vpa)
    if (allocated(maxwell_vpa)) deallocate (maxwell_vpa)
    if (allocated(ztmax)) deallocate (ztmax)

  end subroutine finish_vpa_grid

  subroutine init_mu_grid

    use constants, only: pi
    use gauss_quad, only: get_laguerre_grids
    use zgrid, only: nzgrid, nztot
    use geometry, only: bmag, nalpha
    
    implicit none

    real, dimension (:), allocatable :: dmu

    ! allocate arrays and initialize to zero
    if (.not. allocated(mu)) then
       allocate (mu(nmu)) ; mu = 0.0
       allocate (wgts_mu(nmu)) ; wgts_mu = 0.0
       allocate (maxwell_mu(nalpha,-nzgrid:nzgrid,nmu)) ; maxwell_mu = 0.0
    end if

    allocate (dmu(nmu-1)) ; dmu = 0.0
    
    ! dvpe * vpe = d(2*mu*B(z=0)) * B/2B(z=0)
    
    ! use Gauss-Laguerre quadrature in 2*mu*bmag(z=0)
    call get_laguerre_grids (mu, wgts_mu)
    wgts_mu = wgts_mu*exp(mu)/(2.*bmag(1,0))
    
    ! get mu grid from grid in 2*mu*bmag(z=0)
    mu = mu/(2.*bmag(1,0))
       
    ! factor of 2./sqrt(pi) necessary to account for 2pi from 
    ! integration over gyro-angle and 1/pi^(3/2) normalization
    ! of velocity space Jacobian
    ! note that a factor of bmag is missing and will have to be
    ! applied when doing integrals
    wgts_mu = wgts_mu*2./sqrt(pi)

    ! this is the mu part of the v-space Maxwellian
    maxwell_mu = exp(-2.*spread(spread(mu,1,nalpha),2,nztot)*spread(bmag,3,nmu))

    deallocate (dmu)

  end subroutine init_mu_grid

  subroutine finish_mu_grid

    implicit none

    if (allocated(mu)) deallocate (mu)
    if (allocated(wgts_mu)) deallocate (wgts_mu)
    if (allocated(maxwell_mu)) deallocate (maxwell_mu)

  end subroutine finish_mu_grid

  subroutine finish_vpamu_grids

    implicit none
    
    call finish_vpa_grid
    call finish_mu_grid

  end subroutine finish_vpamu_grids

end module vpamu_grids
