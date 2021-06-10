public enum FileHandleError:Error {	
	case error_unknown;		//catchall
	
	case error_access;		//EACCES
	case error_busy;		//EBUSY | ETXTBSY
	case error_quota;		//EQUOT
	case error_exists		//EXIST
	case error_fault		//EFAULT
	case error_fileTooBig	//EFBIG
	case error_isDirectory	//EISDIR
	case error_linkLoop		//ELOOP
	case error_fdLimit		//EMFILE
	case error_nameTooLong	//ENAMETOOLONG
	case error_fileLimit	//ENFILE
	case error_noDevice		//ENODEV
	case error_doesntExist	//ENOENT
	case error_noMemory		//ENOMEM
	case error_notDirectory	//ENOTDIR
	case error_noReader		//ENXIO
	case error_notSupported	//ENOTSUPP
	case error_overflow		//EOVERFLOW
	case error_permission	//EPERM
	case error_readOnly		//EROFS
	
	case error_again; 		//EAGAIN
	case error_wouldBlock;	//EWOULDBLOCK
	case error_bad_fh;		//EBADF
	case error_interrupted;	//EINTR
	case error_invalid;		//EINVAL
	case error_io;			//EIO
	case error_noSpace;		//ENOSPC
	
	case error_pipe;		//EPIPE
}