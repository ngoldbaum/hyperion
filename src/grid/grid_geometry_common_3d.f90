module grid_geometry

  use core_lib
  use mpi_core
  use mpi_io
  use type_grid_cell
  use grid_io, only : read_grid_3d
  use grid_geometry_specific

  implicit none
  save

  private

  ! Imported from grid-specific module
  public :: grid_geometry_debug
  public :: find_cell
  public :: next_cell
  public :: place_in_cell
  public :: in_correct_cell
  public :: random_position_cell
  public :: find_wall
  public :: distance_to_closest_wall
  public :: setup_grid_geometry
  public :: geo
  public :: escaped
  public :: cell_width

  public :: opposite_wall
  public :: random_cell

  public :: grid_load_pdf_map
  public :: grid_sample_pdf_map
  public :: grid_sample_pdf_map2

contains

  integer function opposite_wall(wall)
    implicit none
    integer,intent(in) :: wall
    opposite_wall = wall + 2*mod(wall,2) - 1
  end function opposite_wall

  subroutine grid_load_pdf_map(group, path, pdf)

    implicit none

    integer(hid_t),intent(in) :: group
    character(len=*), intent(in) :: path
    type(pdf_discrete_dp), intent(out) :: pdf
    real(dp), allocatable :: map(:)

    ! Read in map from file
    allocate(map(geo%n_cells))
    call read_grid_3d(group, path, map, geo)

    ! Set up PDF to sample map
    call set_pdf(pdf, map)

  end subroutine grid_load_pdf_map

  subroutine grid_sample_pdf_map(pdf, icell)
    implicit none
    type(pdf_discrete_dp), intent(in) :: pdf
    type(grid_cell),intent(out) :: icell
    icell = new_grid_cell(sample_pdf(pdf), geo)
  end subroutine grid_sample_pdf_map

  subroutine grid_sample_pdf_map2(pdf, icell, prob)

    implicit none

    type(pdf_discrete_dp), intent(in) :: pdf
    type(grid_cell),intent(out) :: icell
    integer :: ic
    real(dp) :: prob
    real(dp) :: xi

    do
       call random(xi)
       ic = ceiling(xi * pdf%n)
       prob = pdf%pdf(ic)
       if(prob > 1.e-100_dp) exit
    end do

    icell = new_grid_cell(ic, geo)

    prob = prob * pdf%n

  end subroutine grid_sample_pdf_map2

  type(grid_cell) function random_cell()
    implicit none
    real(dp) :: xi
    integer :: ic
    call random(xi)
    ic = ceiling(xi * geo%n_cells)
    random_cell = new_grid_cell(ic, geo)
  end function random_cell

end module grid_geometry
