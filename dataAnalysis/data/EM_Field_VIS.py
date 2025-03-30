import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
from ipywidgets import interact, FloatSlider

# Constants
omega = 1e6  # Angular frequency (rad/s)
t = 0.0      # Fixed time (you can adjust or animate this if desired)

# Create a 3D cylindrical grid
rho = np.linspace(0.5, 1.5, 10)  # Radial distance (avoid rho=0 to prevent division by zero)
phi = np.linspace(0, 2*np.pi, 36)  # Azimuthal angle
z = np.linspace(-1, 1, 20)         # Axial direction
Rho, Phi, Z = np.meshgrid(rho, phi, z, indexing='ij')

# Convert cylindrical to Cartesian coordinates for plotting
X = Rho * np.cos(Phi)
Y = Rho * np.sin(Phi)
Z = Z

# Function to plot the fields with adjustable H0 and beta
def plot_fields(H0=1.0, beta=1.0):
    # Compute E and H in cylindrical coordinates
    E_phi = (50 / Rho) * np.cos(omega * t + beta * Z)  # E in phi-direction
    H_rho = (H0 / Rho) * np.cos(omega * t + beta * Z)  # H in rho-direction

    # Convert to Cartesian components
    # phi-direction: (-sin(phi), cos(phi), 0)
    # rho-direction: (cos(phi), sin(phi), 0)
    E_x = -E_phi * np.sin(Phi)
    E_y = E_phi * np.cos(Phi)
    E_z = np.zeros_like(E_x)  # No z-component for E

    H_x = H_rho * np.cos(Phi)
    H_y = H_rho * np.sin(Phi)
    H_z = np.zeros_like(H_x)  # No z-component for H

    # Create a 3D plot
    fig = plt.figure(figsize=(12, 6))

    # Plot E-field
    ax1 = fig.add_subplot(121, projection='3d')
    ax1.quiver(X, Y, Z, E_x, E_y, E_z, color='b', length=0.5, normalize=True)
    ax1.set_title(f'E-field (H0={H0}, β={beta})')
    ax1.set_xlabel('X')
    ax1.set_ylabel('Y')
    ax1.set_zlabel('Z')
    ax1.set_xlim(-2, 2)
    ax1.set_ylim(-2, 2)
    ax1.set_zlim(-1, 1)

    # Plot H-field
    ax2 = fig.add_subplot(122, projection='3d')
    ax2.quiver(X, Y, Z, H_x, H_y, H_z, color='r', length=0.5, normalize=True)
    ax2.set_title(f'H-field (H0={H0}, β={beta})')
    ax2.set_xlabel('X')
    ax2.set_ylabel('Y')
    ax2.set_zlabel('Z')
    ax2.set_xlim(-2, 2)
    ax2.set_ylim(-2, 2)
    ax2.set_zlim(-1, 1)

    plt.tight_layout()
    plt.show()

# Create interactive sliders for H0 and beta
interact(plot_fields,
         H0=FloatSlider(min=0.1, max=5.0, step=0.1, value=1.0, description='H0'),
         beta=FloatSlider(min=0.1, max=5.0, step=0.1, value=1.0, description='β'))