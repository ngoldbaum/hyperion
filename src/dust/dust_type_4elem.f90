module type_dust

  use core_lib

  implicit none
  save

  private
  public :: dust
  public :: dust_setup
  public :: dust_emit
  public :: dust_emit_peeloff
  public :: dust_scatter
  public :: dust_scatter_peeloff
  public :: dust_sample_emit_probability
  public :: dust_sample_emit_frequency
  public :: dust_jnu_var_pos_frac

  type dust

     ! Optical properties
     integer :: n_nu                              ! number of frequencies
     real(dp),allocatable :: nu(:),log_nu(:)      ! Frequency
     real(dp),allocatable :: albedo_nu(:)         ! Albedo 
     real(dp),allocatable :: chi_nu(:)          ! Opacity
     real(dp),allocatable :: kappa_nu(:)      ! Opacity to absorption

     ! Scattering matrix
     integer :: n_mu                              ! number of cos(theta)
     real(dp),allocatable :: mu(:)                ! Values of cos(theta) that P is tabulated for
     real(dp),allocatable :: P1(:,:),P2(:,:),P3(:,:),P4(:,:) ! 4-element P matrix
     real(dp),allocatable :: P1_cdf(:,:),P2_cdf(:,:),P3_cdf(:,:),P4_cdf(:,:) ! 4-element P matrix
     real(dp),allocatable :: I_max(:)
     real(dp) :: mu_min, mu_max                   ! range of mu values

     ! Mean opacities
     integer :: n_t                               ! number of temperatures
     real(dp),allocatable :: T(:)                 ! Temperature
     real(dp),allocatable :: log10_T(:)           ! Temperature [Log10]
     real(dp),allocatable :: chi_planck(:)       ! planck mean opacity
     real(dp),allocatable :: kappa_planck(:)   ! planck mean absoptive opacity
     real(dp),allocatable :: chi_rosseland(:)   ! Rosseland mean opacity
     real(dp),allocatable :: kappa_rosseland(:)  ! Rosseland mean opacity
     real(dp),allocatable :: energy_abs_per_mass(:)        ! Corresponding absorbed energy per unit mass

     ! Emissivity
     integer :: n_jnu                             ! number of emissivities
     character(len=1) :: emiss_var                ! type of independent emissivity variable
     real(dp),allocatable :: j_nu_var(:)          ! independent emissivity variable
     real(dp),allocatable :: log10_j_nu_var(:)    ! independent emissivity variable [Log10]
     type(pdf_dp),allocatable :: j_nu(:)          ! emissivity

     ! integer :: beta ! power of the photon energy sampling
     ! real(dp),allocatable  :: a(:) ! Energy of the emitted photon = a*nu^beta * incoming energy

  end type dust

contains

  subroutine dust_setup(group,d,beta)

    implicit none

    integer(hid_t),intent(in) :: group
    type(dust),intent(out)    :: d
    real(dp),intent(in)       :: beta
    integer :: i,j
    real(dp),allocatable :: emiss_nu(:), emiss_jnu(:,:)
    real(dp) :: norm, dmu
    character(len=100) :: path

    ! Read dust file

    call hdf5_read_keyword(group, '.', 'emissvar', d%emiss_var)

    ! OPTICAL PROPERTIES

    path = 'Optical properties'
    call hdf5_table_read_column_auto(group,path,'nu',d%nu)
    call hdf5_table_read_column_auto(group,path,'albedo',d%albedo_nu)
    call hdf5_table_read_column_auto(group,path,'chi',d%chi_nu)
    call hdf5_table_read_column_auto(group,path,'P1',d%P1)
    call hdf5_table_read_column_auto(group,path,'P2',d%P2)
    call hdf5_table_read_column_auto(group,path,'P3',d%P3)
    call hdf5_table_read_column_auto(group,path,'P4',d%P4)

    ! Check for NaN values
    if(any(d%nu.ne.d%nu)) call error("dust_setup","nu array contains NaN values")
    if(any(d%albedo_nu.ne.d%albedo_nu)) call error("dust_setup","albedo_nu array contains NaN values")
    if(any(d%chi_nu.ne.d%chi_nu)) call error("dust_setup","chi_nu array contains NaN values")    
    if(any(d%P1.ne.d%P1)) call error("dust_setup","P1 matrix contains NaN values")
    if(any(d%P2.ne.d%P2)) call error("dust_setup","P2 matrix contains NaN values")
    if(any(d%P3.ne.d%P3)) call error("dust_setup","P3 matrix contains NaN values")
    if(any(d%P4.ne.d%P4)) call error("dust_setup","P4 matrix contains NaN values")

    ! Find number of frequencies
    d%n_nu = size(d%nu)

    ! Compute log[nu]
    allocate(d%log_nu(d%n_nu))
    d%log_nu = log10(d%nu)

    ! Compute opacity to absorption
    allocate(d%kappa_nu(d%n_nu))
    d%kappa_nu = d%chi_nu * (1._dp - d%albedo_nu)

    ! Compute maximum scattering intensity vs wavelength
    allocate(d%I_max(d%n_nu))
    do j=1,d%n_nu
       d%I_max(j) = maxval(d%P1(:,j)+abs(d%P2(:,j)))
    end do

    path = 'Scattering angles'
    call hdf5_table_read_column_auto(group,path,'mu',d%mu)

    ! Check for NaN values
    if(any(d%mu.ne.d%mu)) call error("dust_setup","mu array contains NaN values")

    ! Find number of scattering angles
    d%n_mu = size(d%mu)

    ! Find min and max
    d%mu_min = d%mu(1)
    d%mu_max = d%mu(d%n_mu)

    dmu = d%mu_max - d%mu_min

    ! Normalize scattering matrix. The probability distribution functions
    ! are normalized so that their total integrals are 4*pi (not 1)
    do j=1,d%n_nu
       norm = integral_linlog(d%mu, d%P1(:,j))
       if(norm.eq.0._dp) call error("dust_setup", "P1 matrix normalization is zero")
       d%P1(:,j) = d%P1(:,j) / norm * dmu
       d%P2(:,j) = d%P2(:,j) / norm * dmu
       d%P3(:,j) = d%P3(:,j) / norm * dmu
       d%P4(:,j) = d%P4(:,j) / norm * dmu
    end do

    ! Allocate cumulative scattering matrix elements
    allocate(d%P1_cdf(size(d%P1,1), size(d%P1,2)))
    allocate(d%P2_cdf(size(d%P2,1), size(d%P2,2)))
    allocate(d%P3_cdf(size(d%P3,1), size(d%P3,2)))
    allocate(d%P4_cdf(size(d%P4,1), size(d%P4,2)))

    ! Find cumulative scattering matrix elements
    ! TODO: can be optimized by doing a running integral
    do j=1,d%n_nu
       do i=1,d%n_mu
          d%P1_cdf(i,j) = integral(d%mu, d%P1(:,j), d%mu(1), d%mu(i))
          d%P2_cdf(i,j) = integral(d%mu, d%P2(:,j), d%mu(1), d%mu(i))
          d%P3_cdf(i,j) = integral(d%mu, d%P3(:,j), d%mu(1), d%mu(i))
          d%P4_cdf(i,j) = integral(d%mu, d%P4(:,j), d%mu(1), d%mu(i))
       end do
       if(.not.all(d%P1_cdf(:,j)==0.)) d%P1_cdf(:,j) = d%P1_cdf(:,j) / d%P1_cdf(d%n_mu, j)
       if(.not.all(d%P2_cdf(:,j)==0.)) d%P2_cdf(:,j) = d%P2_cdf(:,j) / d%P2_cdf(d%n_mu, j)
       if(.not.all(d%P3_cdf(:,j)==0.)) d%P3_cdf(:,j) = d%P3_cdf(:,j) / d%P3_cdf(d%n_mu, j)
       if(.not.all(d%P4_cdf(:,j)==0.)) d%P4_cdf(:,j) = d%P4_cdf(:,j) / d%P4_cdf(d%n_mu, j)
    end do

    ! MEAN OPACITIES

    path = 'Mean opacities'
    call hdf5_table_read_column_auto(group,path,'temperature',d%T)
    call hdf5_table_read_column_auto(group,path,'chi_planck',d%chi_planck)
    call hdf5_table_read_column_auto(group,path,'kappa_planck',d%kappa_planck)
    call hdf5_table_read_column_auto(group,path,'chi_rosseland',d%chi_rosseland)
    call hdf5_table_read_column_auto(group,path,'kappa_rosseland',d%kappa_rosseland)

    ! Check for NaN values
    if(any(d%T.ne.d%T)) call error("dust_setup","temperature array contains NaN values")
    if(any(d%chi_planck.ne.d%chi_planck)) call error("dust_setup","chi_planck array contains NaN values")
    if(any(d%kappa_planck.ne.d%kappa_planck)) call error("dust_setup","kappa_planck array contains NaN values")
    if(any(d%chi_rosseland.ne.d%chi_rosseland)) call error("dust_setup","chi_planck array contains NaN values")
    if(any(d%kappa_rosseland.ne.d%kappa_rosseland)) call error("dust_setup","kappa_rosseland array contains NaN values")

    d%n_t = size(d%T)
    allocate(d%log10_T(d%n_t))
    d%log10_T = log10(d%T)

    ! Precompute required absorbed energy
    allocate(d%energy_abs_per_mass(d%n_t))
    d%energy_abs_per_mass = d%T**4 * d%kappa_planck * 4._dp * stef_boltz

    do i=2,d%n_t
       if(d%energy_abs_per_mass(i) < d%energy_abs_per_mass(i-1)) then
          call error("dust_setup","energy per unit mass is not monotonically increasing")
       end if
    end do

    ! need to check monotonically increases

    ! EMISSIVITIES

    path = 'Emissivities'
    call hdf5_table_read_column_auto(group,path,'nu',emiss_nu)
    call hdf5_table_read_column_auto(group,path,'jnu',emiss_jnu)

    ! Check for NaN values
    if(any(emiss_nu.ne.emiss_nu)) call error("dust_setup","emiss_nu array contains NaN values")
    if(any(emiss_jnu.ne.emiss_jnu)) call error("dust_setup","emiss_jnu array contains NaN values")

    path = 'Emissivity variable'
    select case (d%emiss_var)
    case('T')
       call hdf5_table_read_column_auto(group,path,'temperature',d%j_nu_var)
       if(any(d%j_nu_var.ne.d%j_nu_var)) call error("dust_setup","temperature array contains NaN values")
    case('E')
       call hdf5_table_read_column_auto(group,path,'specific_energy_abs',d%j_nu_var)
       if(any(d%j_nu_var.ne.d%j_nu_var)) call error("dust_setup","specific_energy_abs array contains NaN values")
    case default
       stop "Unknown EMISSVAR"
    end select

    ! Find number of emissivites
    d%n_jnu = size(d%j_nu_var)
    allocate(d%log10_j_nu_var(d%n_jnu))
    d%log10_j_nu_var = log10(d%j_nu_var)

    ! Allocate emissivity PDF
    allocate(d%j_nu(d%n_jnu))

    do i=1,d%n_jnu
       call set_pdf(d%j_nu(i),emiss_nu,emiss_jnu(i,:),log=.true.)
    end do

    ! Set power of energy sampling
    ! d%beta = beta   
    ! do i=1,n_t          
    !   call set_pdf(d%j_nu(i),d%nu,d%kappa_nu*B_nu(d%nu,d%T(i))*d%nu**(-d%beta),log=.true.)
    !   ! Find a
    !   d%a(i) = integral(d%nu,d%kappa_nu*B_nu(d%nu,d%T(i))*d%nu**(-d%beta)) &
    !   &      / integral(d%nu,d%kappa_nu*B_nu(d%nu,d%T(i)))
    ! end do

  end subroutine dust_setup

  subroutine dust_jnu_var_pos_frac(d,temperature,specific_energy_abs,jnu_var_id,jnu_var_frac)
    implicit none
    type(dust),intent(in) :: d
    real(dp),intent(in) :: temperature,specific_energy_abs
    integer,intent(out) :: jnu_var_id
    real(dp),intent(out) :: jnu_var_frac
    real(dp) :: jnu_var

    select case(d%emiss_var)
    case('T')
       jnu_var = temperature    
    case('E')
       jnu_var = specific_energy_abs
    end select

    if(jnu_var < d%j_nu_var(1)) then
       jnu_var_id = 1
       jnu_var_frac = 0._dp
    else if(jnu_var > d%j_nu_var(size(d%j_nu_var))) then
       jnu_var_id = size(d%j_nu_var) - 1
       jnu_var_frac = 1._dp
    else
       jnu_var_id = locate(d%j_nu_var,jnu_var)
       jnu_var_frac = (log10(jnu_var) - d%log10_j_nu_var(jnu_var_id)) &
            &       / (d%log10_j_nu_var(jnu_var_id + 1) - d%log10_j_nu_var(jnu_var_id))
    end if

  end subroutine dust_jnu_var_pos_frac

  subroutine dust_emit_peeloff(d,nu,a,s,a_req)
    implicit none
    type(dust),intent(in)          :: d
    real(dp),intent(in)            :: nu
    type(angle3d_dp),intent(inout) :: a
    type(stokes_dp),intent(inout)  :: s
    type(angle3d_dp),intent(in)    :: a_req
    ! The probability distribution function for the redistribution is
    ! normalized so that its total integral is 4*pi (not 1)
    a = a_req
  end subroutine dust_emit_peeloff

  subroutine dust_emit(d,jnu_var_id,jnu_var_frac,nu,a,s,energy_scaling)

    implicit none

    type(dust),intent(in)          :: d
    integer,intent(in)             :: jnu_var_id
    real(dp),intent(in)            :: jnu_var_frac
    type(angle3d_dp),intent(out)   :: a
    type(stokes_dp),intent(out)    :: s
    real(dp),intent(out)           :: nu
    real(dp),intent(out)           :: energy_scaling

    call dust_sample_emit_frequency(d,jnu_var_id,jnu_var_frac,nu)

    s = stokes_dp(1._dp,0._dp,0._dp,0._dp)

    energy_scaling = 1.
    ! energy_scaling = d%a(i)*nu**(d%beta)

    call random_sphere_angle3d(a)

  end subroutine dust_emit

  subroutine dust_sample_emit_probability(d,jnu_var_id,jnu_var_frac,nu, prob)

    implicit none

    type(dust),intent(in)          :: d
    integer,intent(in)             :: jnu_var_id
    real(dp),intent(in)            :: jnu_var_frac, nu
    real(dp),intent(out)           :: prob

    real(dp) :: prob1,prob2

    prob1 = interpolate_pdf(d%j_nu(jnu_var_id), nu, bounds_error=.false., fill_value=0._dp)
    prob2 = interpolate_pdf(d%j_nu(jnu_var_id+1), nu, bounds_error=.false., fill_value=0._dp)

    if(prob1.eq.0._dp.or.prob2.eq.0._dp) then
       prob = 0._dp
    else
       prob = log10(prob1) + jnu_var_frac * (log10(prob2) - log10(prob1))
       prob = 10._dp**prob
    end if

  end subroutine dust_sample_emit_probability

  subroutine dust_sample_emit_frequency(d,jnu_var_id,jnu_var_frac,nu)

    implicit none

    type(dust),intent(in)          :: d
    integer,intent(in)             :: jnu_var_id
    real(dp),intent(in)            :: jnu_var_frac
    real(dp),intent(out)           :: nu

    real(dp) :: nu1,nu2,xi

    call random(xi)

    nu1 = sample_pdf(d%j_nu(jnu_var_id),xi)
    nu2 = sample_pdf(d%j_nu(jnu_var_id+1),xi)

    nu = log10(nu1) + jnu_var_frac * (log10(nu2) - log10(nu1))
    nu = 10._dp**nu

  end subroutine dust_sample_emit_frequency

  subroutine dust_scatter_peeloff(d,nu,a,s,a_req)
    implicit none
    type(dust),intent(in)          :: d
    real(dp),intent(in)            :: nu
    type(angle3d_dp),intent(inout) :: a
    type(stokes_dp),intent(inout)  :: s
    type(angle3d_dp),intent(in)    :: a_req
    type(angle3d_dp) :: a_scat  
    real(dp) :: P1,P2,P3,P4
    call difference_angle3d(a, a_req, a_scat)
    if(a_scat%cost < d%mu_min .or. a_scat%cost > d%mu_max) then
       s%i = 0.
       s%q = 0.
       s%u = 0.
       s%v = 0.
    else
       P1 = interp2d(d%mu,d%nu,d%P1,a_scat%cost,nu)
       P2 = interp2d(d%mu,d%nu,d%P2,a_scat%cost,nu)
       P3 = interp2d(d%mu,d%nu,d%P3,a_scat%cost,nu)
       P4 = interp2d(d%mu,d%nu,d%P4,a_scat%cost,nu)
       call scatter_stokes(s,a,a_scat,a_req,P1,P2,P3,P4)
    end if
    a = a_req
  end subroutine dust_scatter_peeloff

  subroutine dust_scatter(d,nu,a,s)

    implicit none

    type(dust),intent(in)                :: d
    type(angle3d_dp),intent(inout)       :: a
    type(stokes_dp),intent(inout)        :: s

    real(dp) :: nu

    type(angle3d_dp) :: a_scat
    type(angle3d_dp) :: a_final

    real(dp) :: P1,P2,P3,P4,norm

    real(dp) :: c1, c2, ctot, cdf1, cdf2, xi
    real(dp) :: sin_2_i1,cos_2_i1

    integer :: imin, imax, imu, inu

    integer :: iter
    integer,parameter :: maxiter = 1000000

    !#############################################################################
    !
    ! In order to sample the scattering angle, we first sample two angles
    ! theta and phi uniformly.
    !
    ! We then calculate the new value of I using these values, and the previous
    ! values of the Stokes parameters, and we decide whether to keep it using
    ! the rejection criterion
    !
    !#############################################################################

    call random_sphere_angle3d(a_scat)

    sin_2_i1 =         2._dp * a_scat%sinp * a_scat%cosp
    cos_2_i1 = 1._dp - 2._dp * a_scat%sinp * a_scat%sinp

    c1 = s%I
    c2 = (cos_2_i1 * s%Q - sin_2_i1 * s%U)
    ctot = c1 + c2
    c1 = c1 / ctot
    c2 = c2 / ctot

    imin = 1
    imax = d%n_mu
    inu = locate(d%nu, nu)
    ! TODO: interpolate in nu as well

    if(inu==-1) then

       ! Frequency is out of bounds, use isotropic scattering
       P1 = 1._dp
       P2 = 0._dp
       P3 = 0._dp
       P4 = 0._dp

    else

       call random_number(xi)

       do iter=1,maxiter
          imu = (imax + imin) / 2
          cdf1 = c1 * d%P1_cdf(imu, inu) + c2 * d%P2_cdf(imu, inu)
          cdf2 = c1 * d%P1_cdf(imu+1, inu) + c2 * d%P2_cdf(imu+1, inu)
          if(xi > cdf2) then
             imin = imu
          else if(xi < cdf1) then
             imax = imu
          else
             exit
          end if
          if(imin==imax) stop "ERROR: in sampling mu for scattering"
       end do

       if(iter==maxiter+1) stop "ERROR: stuck in do loop in dust_scatter"

       a_scat%cost = (xi - cdf1) / (cdf2 - cdf1) * (d%mu(imu+1) - d%mu(imu)) + d%mu(imu)
       a_scat%sint = sqrt(1._dp - a_scat%cost*a_scat%cost)

       P1 = interp2d(d%mu,d%nu,d%P1,a_scat%cost,nu)
       P2 = interp2d(d%mu,d%nu,d%P2,a_scat%cost,nu)
       P3 = interp2d(d%mu,d%nu,d%P3,a_scat%cost,nu)
       P4 = interp2d(d%mu,d%nu,d%P4,a_scat%cost,nu)

    end if

    ! Find new photon direction
    call rotate_angle3d(a_scat,a,a_final)

    ! Compute how the stokes parameters are changed by the interaction
    call scatter_stokes(s,a,a_scat,a_final,P1,P2,P3,P4) 

    ! Change photon direction
    a = a_final

    norm = 1._dp / S%I

    S%I = 1._dp
    S%Q = S%Q * norm
    S%U = S%U * norm
    S%V = S%V * norm   

  end subroutine dust_scatter

  !#############################################################################
  !
  ! To find how the stokes parameters S = (I,Q,U,V) change with the scattering
  ! interaction, use the following equation:
  !
  ! S = L( pi - i_2 ) * R * L( - i_1 ) * S'
  !
  ! S' is the old set of Stokes parameters
  ! L ( - i_1 ) is a rotation matrix to rotate into the plane of scattering
  ! R calculates the scattering function
  ! L ( pi - i_2 ) rotates back to the observer's frame of reference
  !
  ! The rotation matrix L is given by
  !
  !          /  1  |      0      |      0      |  0  \
  ! L(psi) = |  0  | +cos(2*psi) | +sin(2*psi) |  0  |
  !          |  0  | -sin(2*psi) | +cos(2*psi) |  0  |
  !          \  0  |      0      |      0      |  1  /
  !
  ! The scattering matrix can have various number of elements.
  !
  ! The electron or dust scattering properties are recorded in the R matrix.
  !
  ! For example, a four element matrix could be:
  !
  !                /  P1  P2  0   0  \
  ! R(theta) = a * |  P2  P1  0   0  |
  !                |  0   0   P3 -P4 |
  !                \  0   0   P4  P3 /
  !
  ! The values of P1->4 can either be found from an analytical function, or
  ! read in from files.
  !
  !#############################################################################

  subroutine scatter_stokes(s,a_coord,a_scat,a_final,P1,P2,P3,P4)

    implicit none

    type(angle3d_dp),intent(in)    :: a_coord     ! The photon direction angle
    type(angle3d_dp),intent(in)    :: a_scat      ! The photon scattering angle
    type(angle3d_dp),intent(in)    :: a_final     ! The final photon direction
    type(stokes_dp),intent(inout)  :: s           ! The Stokes parameters of the photon
    real(dp),intent(in)            :: P1,P2,P3,P4 ! 4-element matrix elements

    ! Spherical trigonometry
    real(dp) :: cos_a,sin_a
    real(dp) :: cos_b,sin_b
    real(dp) :: cos_c,sin_c
    real(dp) :: cos_big_a,sin_big_a
    real(dp) :: cos_big_b,sin_big_b
    real(dp) :: cos_big_c,sin_big_c

    ! Local
    real(dp) :: cos_i2,cos_2_i2
    real(dp) :: sin_i2,sin_2_i2
    real(dp) :: cos_2_alpha,cos_2_beta
    real(dp) :: sin_2_alpha,sin_2_beta
    real(dp) :: RLS1,RLS2,RLS3,RLS4

    ! The general spherical trigonometry routines in type_angle3d have served
    ! us well this far, but now we need to compute a specific angle in the
    ! spherical triangle. The meaning of the angles is as follows:

    ! a =   old theta angle (initial direction angle)
    ! b = local theta angle (scattering or emission angle)
    ! c =   new theta angle (final direction angle)

    ! A = what we want to calculate here
    ! B = new phi - old phi
    ! C = local phi angle (scattering or emission angle)

    cos_a = a_coord%cost
    sin_a = a_coord%sint

    cos_b = a_scat%cost
    sin_b = a_scat%sint

    cos_c = a_final%cost
    sin_c = a_final%sint

    cos_big_b = a_coord%cosp * a_final%cosp + a_coord%sinp * a_final%sinp
    sin_big_b = a_coord%sinp * a_final%cosp - a_coord%cosp * a_final%sinp

    cos_big_C = a_scat%cosp
    sin_big_C = abs(a_scat%sinp)

    if(sin_big_c < 10. * tiny(1._dp) .and. sin_c < 10. * tiny(1._dp)) then
       cos_big_a = - cos_big_b * cos_big_c
       sin_big_a = sqrt(1._8 - cos_big_a * cos_big_a)
    else
       cos_big_a = (cos_a - cos_b * cos_c) / (sin_b * sin_c)
       sin_big_a = + sin_big_c * sin_a / sin_c
    end if

    cos_i2 = cos_big_a
    sin_i2 = sin_big_a

    cos_2_i2    = 1._dp - 2._dp * sin_i2 * sin_i2
    sin_2_i2    =         2._dp * sin_i2 * cos_i2

    cos_2_alpha = 1._dp - 2._dp * a_scat%sinp * a_scat%sinp
    sin_2_alpha =       - 2._dp * a_scat%sinp * a_scat%cosp

    if(a_scat%sinp < 0.) then
       cos_2_beta =  cos_2_i2
       sin_2_beta =  sin_2_i2
    else
       cos_2_beta =  cos_2_i2
       sin_2_beta = -sin_2_i2
    end if

    RLS1 =   P1 * S%I + P2 * ( + cos_2_alpha * S%Q + sin_2_alpha * S%U )
    RLS2 =   P2 * S%I + P1 * ( + cos_2_alpha * S%Q + sin_2_alpha * S%U )
    RLS3 = - P4 * S%V + P3 * ( - sin_2_alpha * S%Q + cos_2_alpha * S%U )
    RLS4 =   P3 * S%V + P4 * ( - sin_2_alpha * S%Q + cos_2_alpha * S%U )

    S%I = RLS1
    S%Q = + cos_2_beta * RLS2 + sin_2_beta * RLS3
    S%U = - sin_2_beta * RLS2 + cos_2_beta * RLS3
    S%V = RLS4

  end subroutine scatter_stokes

  elemental real(dp) function B_nu(nu,T)
    implicit none
    real(dp),intent(in) :: nu,T
    real(dp),parameter :: a = two * h_cgs / c_cgs / c_cgs
    real(dp),parameter :: b = h_cgs / k_cgs
    B_nu = a * nu * nu * nu / ( exp(b*nu/T) - one)
  end function B_nu

  elemental real(dp) function dB_nu_over_dT(nu,T)
    implicit none
    real(dp),intent(in) :: nu,T
    real(dp),parameter :: a = two * h_cgs * h_cgs / c_cgs / c_cgs / k_cgs
    real(dp),parameter :: b = h_cgs / k_cgs
    dB_nu_over_dT = a * nu * nu * nu * nu * exp(b*nu/T) / (exp(b*nu/T) - one)**2.
  end function dB_nu_over_dT

end module type_dust
