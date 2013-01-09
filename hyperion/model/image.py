import numpy as np

from ..util.functions import FreezableClass, is_numpy_array
from ..util.constants import c


class Image(FreezableClass):
    """
    Class to represent an image or set of images

    Parameters
    ----------
    nu : ndarray
        The frequencies at which the image is defined, in Hz
    flux : ndarray, optional
        The fluxes for the image. The last dimensions should match the number
        of frequencies. This flux can be f_nu or nu * f_nu.
    unc : ndarray, optional
        The flux uncertainties for the image. The last dimensions should match
        the number of frequencies.
    units : str
        The units of the flux
    """

    def __init__(self, nu, flux=None, unc=None, units=None):

        self.nu = nu
        self.flux = flux
        self.unc = unc
        self.units = units

        self.x_min = None
        self.x_max = None
        self.y_min = None
        self.y_max = None

        self.lon_min = None
        self.lon_max = None
        self.lat_min = None
        self.lat_max = None

        self.distance = None

        self.pix_area_sr = None

        self._freeze()

    @property
    def nu(self):
        return self._nu

    @nu.setter
    def nu(self, value):
        if type(value) in [list, tuple]:
            value = np.array(value)
        if value is None:
            self._nu = value
        elif isinstance(value, np.ndarray) and value.ndim == 1:
            self._nu = value
        else:
            raise TypeError("nu should be a 1-d sequence")

    @property
    def flux(self):
        return self._flux

    @flux.setter
    def flux(self, value):
        if type(value) in [list, tuple]:
            value = np.array(value)
        if value is None:
            self._flux = value
        elif isinstance(value, np.ndarray) and value.ndim >= 1:
            if self.nu is not None and len(self.nu) != value.shape[-1]:
                raise ValueError("the last dimension of the flux array should match the length of the nu array (expected {0} but found {1})".format(len(self.nu), value.shape[-1]))
            else:
                if hasattr(self, 'unc') and self.unc is not None:
                    if value.shape != self.unc.shape:
                        raise ValueError("dimensions should match that of unc")
                self._flux = value
        else:
            raise TypeError("flux should be a multi-dimensional array")

    @property
    def unc(self):
        return self._unc

    @unc.setter
    def unc(self, value):
        if type(value) in [list, tuple]:
            value = np.array(value)
        if value is None:
            self._unc = value
        elif isinstance(value, np.ndarray) and value.ndim >= 1:
            if self.nu is not None and len(self.nu) != value.shape[-1]:
                raise ValueError("the last dimension of the unc array should match the length of the nu array (expected {0} but found {1})".format(len(self.nu), value.shape[-1]))
            else:
                if hasattr(self, 'flux') and  self.flux is not None:
                    if value.shape != self.flux.shape:
                        raise ValueError("dimensions should match that of flux")
                self._unc = value
        else:
            raise TypeError("unc should be a multi-dimensional array")
    @property
    def unit(self):
        return self._unit

    @unit.setter
    def unit(self, value):
        if value is None or isinstance(value, basestring):
            self._unit = value
        else:
            raise ValueError("unit should be a string")

    @property
    def wav(self):
        return c / self.nu * 1e4

    def __iter__(self):
        if self.unc is None:
            return (x for x in [self.wav, self.flux])
        else:
            return (x for x in [self.wav, self.flux, self.unc])

    @property
    def x_min(self):
        """
        Lower extent of the image in the x direction in cm.
        """
        return self._x_min

    @x_min.setter
    def x_min(self, value):
        if value is None or (np.isscalar(value) and np.isreal(value)):
            self._x_min = value
        else:
            raise ValueError("x_min should be a real scalar value")

    @property
    def x_max(self):
        """
        Upper extent of the image in the x direction in cm.
        """
        return self._x_max

    @x_min.setter
    def x_max(self, value):
        if value is None or (np.isscalar(value) and np.isreal(value)):
            self._x_max = value
        else:
            raise ValueError("x_max should be a real scalar value")

    @property
    def y_min(self):
        """
        Lower extent of the image in the y direction in cm.
        """
        return self._y_min

    @y_min.setter
    def y_min(self, value):
        if value is None or (np.isscalar(value) and np.isreal(value)):
            self._y_min = value
        else:
            raise ValueError("y_min should be a real scalar value")

    @property
    def y_max(self):
        """
        Upper extent of the image in the y direction in cm.
        """
        return self._y_max

    @y_min.setter
    def y_max(self, value):
        if value is None or (np.isscalar(value) and np.isreal(value)):
            self._y_max = value
        else:
            raise ValueError("y_max should be a real scalar value")

    @property
    def lon_min(self):
        """
        Lower extent of the image in the x direction in degrees.
        """
        return self._lon_min

    @lon_min.setter
    def lon_min(self, value):
        if value is None or (np.isscalar(value) and np.isreal(value)):
            self._lon_min = value
        else:
            raise ValueError("lon_min should be a real scalar value")

    @property
    def lon_max(self):
        """
        Upper extent of the image in the x direction in degrees.
        """
        return self._lon_max

    @lon_min.setter
    def lon_max(self, value):
        if value is None or (np.isscalar(value) and np.isreal(value)):
            self._lon_max = value
        else:
            raise ValueError("lon_max should be a real scalar value")

    @property
    def lat_min(self):
        """
        Lower extent of the image in the y direction in degrees.
        """
        return self._lat_min

    @lat_min.setter
    def lat_min(self, value):
        if value is None or (np.isscalar(value) and np.isreal(value)):
            self._lat_min = value
        else:
            raise ValueError("lat_min should be a real scalar value")

    @property
    def lat_max(self):
        """
        Upper extent of the image in the y direction in degrees.
        """
        return self._lat_max

    @lat_min.setter
    def lat_max(self, value):
        if value is None or (np.isscalar(value) and np.isreal(value)):
            self._lat_max = value
        else:
            raise ValueError("lat_max should be a real scalar value")

    @property
    def distance(self):
        """
        Distance assumed for the image.
        """
        return self._distance

    @lat_min.setter
    def distance(self, value):
        if value is None or (np.isscalar(value) and np.isreal(value)):
            self._distance = value
        else:
            raise ValueError("distance should be a real scalar value")

    @property
    def pix_area_sr(self):
        """
        Pixel area in steradians.
        """
        return self._pix_area_sr

    @lat_min.setter
    def pix_area_sr(self, value):
        if value is None or (np.isscalar(value) and np.isreal(value)) or (is_numpy_array(value) and value.ndim == 2):
            self._lat_max = value
        else:
            raise ValueError("pix_area_sr should be a real scalar value or a 2-d array")