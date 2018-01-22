module neoclassical_terms

  implicit none

  public :: init_neoclassical_terms
  public :: finish_neoclassical_terms
  public :: include_neoclassical_terms
  public :: dfneo_dvpa

  private

  logical :: include_neoclassical_terms
  integer :: nradii
  real :: drho

  integer :: neo_option_switch
  integer, parameter :: neo_option_sfincs = 1

  real, dimension (:,:,:,:,:), allocatable :: f_neoclassical
  real, dimension (:,:,:,:), allocatable :: dfneo_dvpa
  real, dimension (:,:), allocatable :: phi_neoclassical

  logical :: neoinit = .false.

contains

  subroutine init_neoclassical_terms

    use mp, only: proc0
    use zgrid, only: nzgrid
    use vpamu_grids, only: nvgrid, nmu
    use species, only: nspec
    use sfincs_interface, only: get_neo_from_sfincs
    
    implicit none
    
    if (neoinit) return
    neoinit = .true.

    call read_parameters
    if (include_neoclassical_terms) then
       if (.not.allocated(f_neoclassical)) &
            allocate (f_neoclassical(-nzgrid:nzgrid,-nvgrid:nvgrid,nmu,nspec,-nradii/2:nradii/2))
       if (.not.allocated(phi_neoclassical)) &
            allocate (phi_neoclassical(-nzgrid:nzgrid,-nradii/2:nradii/2))
       if (.not.allocated(dfneo_dvpa)) &
            allocate (dfneo_dvpa(-nzgrid:nzgrid,-nvgrid:nvgrid,nmu,nspec))
       select case (neo_option_switch)
       case (neo_option_sfincs)
          call get_neo_from_sfincs (nradii, drho, f_neoclassical, phi_neoclassical)
       end select
       call get_dfneo_dvpa (f_neoclassical(:,:,:,:,0), dfneo_dvpa)
       if (proc0) call write_neoclassical
    end if

  end subroutine init_neoclassical_terms

  subroutine read_parameters

    use mp, only: proc0, broadcast
    use file_utils, only: error_unit, input_unit_exist
    use text_options, only: text_option, get_option_value

    implicit none

    type (text_option), dimension (2), parameter :: neoopts = (/ &
         text_option('default', neo_option_sfincs), &
         text_option('sfincs', neo_option_sfincs) /)
    character (10) :: neo_option

    namelist /neoclassical_input/ include_neoclassical_terms, &
         neo_option

    logical :: exist
    integer :: ierr, in_file

    if (proc0) then
       ! set to .true. to include neoclassical terms in GK equation
       include_neoclassical_terms = .false.
       ! number of radial points used for radial derivatives
       ! of neoclassical quantities
       nradii = 3
       ! spacing in rhoc between radial points used for radial derivatives
       drho = 0.01
       ! option for obtaining neoclassical distribution function and potential
       neo_option = 'sfincs'

       in_file = input_unit_exist("neoclassical_input", exist)
       if (exist) read (unit=in_file, nml=neoclassical_input)

       ierr = error_unit()
       call get_option_value &
            (neo_option, neoopts, neo_option_switch, &
            ierr, "neo_option in neoclassical_input")
    end if

    call broadcast (include_neoclassical_terms)
    call broadcast (neo_option_switch)
    call broadcast (nradii)
    call broadcast (drho)

  end subroutine read_parameters

  subroutine get_dfneo_dvpa (fneo, dfneo)

    use finite_differences, only: fd5pt
    use zgrid, only: nzgrid
    use vpamu_grids, only: nvgrid, nmu, nvpa
    use vpamu_grids, only: dvpa
    use species, only: nspec

    implicit none

    real, dimension (-nzgrid:,-nvgrid:,:,:), intent (in) :: fneo
    real, dimension (-nzgrid:,-nvgrid:,:,:), intent (out) :: dfneo

    integer :: iz, imu, is
    real, dimension (:), allocatable :: tmp1, tmp2

    allocate (tmp1(nvpa), tmp2(nvpa))

    do is = 1, nspec
       do imu = 1, nmu
          do iz = -nzgrid, nzgrid
             ! hack to avoid dealing with negative indices in fd5pt
             tmp1 = fneo(iz,:,imu,is)
             call fd5pt (tmp1, tmp2, dvpa)
             dfneo(iz,:,imu,is) = tmp2
          end do
       end do
    end do

    deallocate (tmp1, tmp2)

  end subroutine get_dfneo_dvpa

  subroutine write_neoclassical

    use file_utils, only: open_output_file, close_output_file
    use species, only: nspec
    use zgrid, only: nzgrid, zed
    use vpamu_grids, only: nvgrid, nmu, vpa, mu
    use geometry, only: bmag

    implicit none

    integer :: neo_unit
    integer :: irad, is, iz, imu, iv

    call open_output_file (neo_unit,'.neoclassical')
    write (neo_unit,'(2a8,6a13)') '#1.rad', '2.spec', '3.zed', '4.mu', '5.vpa', &
         '6.f_neo', '7.dfdvpa_neo', '8.phi_neo'
    do irad = -nradii/2, nradii/2
       do is = 1, nspec
          do iz = -nzgrid, nzgrid
             do imu = 1, nmu
                do iv = -nvgrid, nvgrid
                   write (neo_unit,'(2i8,6e13.5)') irad, is, zed(iz), mu(imu), vpa(iv), &
                        f_neoclassical(iz,iv,imu,is,irad)*exp(2.0*mu(imu)*bmag(1,iz)), dfneo_dvpa(iz,iv,imu,is), &
                        phi_neoclassical(iz,irad)
                end do
                write (neo_unit,*)
             end do
             write (neo_unit,*)
          end do
          write (neo_unit,*)
       end do
       write (neo_unit,*)
    end do
    call close_output_file (neo_unit)

  end subroutine write_neoclassical

  subroutine finish_neoclassical_terms

    implicit none

    if (allocated(f_neoclassical)) deallocate (f_neoclassical)
    if (allocated(phi_neoclassical)) deallocate (phi_neoclassical)
    if (allocated(dfneo_dvpa)) deallocate (dfneo_dvpa)

    neoinit = .false.

  end subroutine finish_neoclassical_terms

end module neoclassical_terms
