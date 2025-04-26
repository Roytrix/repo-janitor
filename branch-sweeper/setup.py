from setuptools import setup, find_packages

setup(
    name="branch-sweeper",
    version="1.0.0",
    description="A tool that automatically cleans up stale branches in GitHub repositories",
    author="GitHub Actions",
    author_email="actions@github.com",
    packages=find_packages(where="scripts"),
    package_dir={"": "scripts"},
    python_requires=">=3.7",
    entry_points={
        "console_scripts": [
            "branch-sweeper=branch_sweeper:main",
            "run-sweeper=branch_sweeper.branch_sweeper:main",
            "run-tests=tests.test_sweeping:main",
        ],
    },
    install_requires=[],  # No external dependencies beyond Python standard library
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Version Control :: Git",
    ],
)
