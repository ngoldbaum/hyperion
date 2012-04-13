import numpy as np
import h5py


def single_grid_dims(data):
    '''
    Find the number of populations, and 3D dimensions

    Parameters
    ----------
    data: list or tuple or np.ndarray or h5py.ExternalLink
        The data to find the number of populations and shape for

    Returns
    -------
    n_pop: int
        Number of (dust) populations
    shape: tuple
        The dimensions of the grid
    '''

    if type(data) in [list, tuple]:

        n_pop = len(data)
        shape = None
        for item in data:
            if shape is None:
                shape = item.shape
            elif item.shape != shape:
                raise ValueError("Grids in list/tuple should have the same "
                                 "dimensions")
        if len(shape) != 3:
            raise ValueError("Grids should be 3-dimensional")

    elif isinstance(data, np.ndarray):

        if data.ndim == 3:
            n_pop = None
            shape = data.shape
        elif data.ndim == 4:
            n_pop = data.shape[0]
            shape = data[0].shape
        else:
            raise Exception("Unexpected number of dimensions: %i" % data.ndim)

    elif isinstance(data, h5py.ExternalLink):

        shape = h5py.File(data.filename, 'r')[data.path].shape

        if len(shape) == 3:
            n_pop = None
        elif len(shape) == 4:
            n_pop = shape[0]
            shape = shape[1:]
        else:
            raise Exception("Unexpected number of dimensions: %i" % data.ndim)
    else:
        raise ValueError("Data should be a list or a Numpy array or an "
                         "external HDF5 link")

    return n_pop, shape